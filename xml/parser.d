// Written in the D programming language.

module xml.parser;

import std.array;
import std.stdint;
import xml.isxml;
import xml.entity;
import xml.attribute;
import xml.txml;
import xml.input;
import xml.dtd;
import xml.util.read;
import xml.error;

import std.conv;
import std.string;
import std.path;
import std.stdio;
import std.variant;
import std.utf;


enum SAX {
    TAG_START, //0
    TAG_SINGLE, //1
    TAG_EMPTY = TAG_SINGLE, // 1
    TAG_END,//2
    TEXT, //3
    CDATA, //4
    COMMENT, //5
    XML_PI, //6
    XML_DEC, //7
    DOC_END,  //8  - is a usefull binary size for an array of delegates
    DOC_TYPE,	/// DTD parse results contained in doctype as DtdValidate.
    XI_NOTATION,
    XI_ENTITY,
    XI_OTHER,		/// internal DOCTYPE declarations
    RET_NULL,  /// nothing returned
    ENUM_LENGTH, /// size of array to hold all the other values
}



enum string xmlAttributeNormalize = "attribute-normalize";
enum string xmlCharFilter = "char-filter";
enum string xmlNamespaces = "namespaces";
enum string xmlFragment = "fragment";

class XmlEvent(T) {
    SAX				    eventId;
    immutable(T)[]		data;
    AttributeMap!T      attributes;
};






/* T is character type of input and results character type.
   Source is filtered via dchar[] for parsing regardless */

alias bool delegate(ref const(dchar)[] buf) MoreInputDg; // For a streamed datasource


class XmlParser(T) {
    private {

        alias  sxml!(T).XmlBuffer XmlBuffer;
        alias  bool function(dchar c) pure	XmlCharTypeFn;
        alias  immutable(T)[] XmlString;

        enum CharFilter
        {
            filterOff, filterOn, filterAlwaysOff
        }
        enum BBCount { b1, b2, bend };
        enum PState
        {
            P_PROLOG, // default, initial state
            P_INT_DTD,
            P_CONTENT, // Content and element alternate
            P_ELEMENT,
            P_END_TAG,
            P_EPILOG,
            P_END
        }

        alias void delegate() ParseStateDg;
    }

    private static struct XmlContext
	{
		int					markupDepth;
		int					elementDepth;
		int					squareDepth;
		int					parenDepth;
		int					docDeclare;
		dchar				front = 0;
		bool				empty  = true;

		double				docVersion_;


		// a single block of unparsed xml

		const(dchar)[]		streamData;	// dynamic stream data
		MoreInputDg			inputDg_;		// more stream data
		uintptr_t			fpos;		 // position in buffer
		EntityData!T		entity;
		bool				scopePop;
		size_t				lineNumber_;
		size_t				lineChar_;
		dchar				lastChar_;
		bool				isEndOfLine_;
		bool				minVersion11_;
		CharFilter			doFilter_;



		this(EntityData!T ed, bool doPop = false)
		{
			entity = ed;
			scopePop = doPop;
		}


	}

    private {
        string				xmlEncoding_;

		bool				validate_;
		bool				isStandalone_;
		bool				namespaceAware_;
		bool				normalizeAttributes_;
		bool				inDTD_;
		bool                isHTML_; // relax some rules for HTML

		bool				isEntity;
		bool				hasDeclaration;
		bool				hasXmlVersion;
		bool				hasStandalone;
		bool				hasEncoding;
		bool				inCharData;


		BBCount				bbct;

		ParseStateDg	    stateDg_;
        PState				state_;

        // stream range mechanics
		dchar[]				backStack;
		const(dchar)[]		streamData_;
		MoreInputDg			inputDg_;

		uintptr_t			fpos;
        dchar				front = 0;
		bool				empty  = true;
        CharFilter			doFilter_;

		// in-parse validation
		int					stackElementDepth;

		// XmlContext
		int					markupDepth;
		int					elementDepth;
		int					squareDepth;
		int					parenDepth;
		int					docDeclare;

		// Source position
		size_t				lineNumber_;
		size_t				lineChar_;
		dchar				lastChar_;

		// External source
		ReadBuffer!(dchar)	fillSource_;
		ulong				fillPos_;
		int					bomMark_;

		bool				isEndOfLine_;
		bool				minVersion11_;

        XmlCharTypeFn		isNameStartFn;
		XmlCharTypeFn		isNameCharFn;

		XmlString[XmlString]	charEntity;

		// buffers for collecting results
		XmlBuffer 	bufNormAttr_, bufAttr_, bufTag_, bufEndTag_,bufMatch_, bufContent_;

        // used by doStartTag
		immutable(T)[]			tag_;
		immutable(T)[]			attrName_;
		immutable(T)[]			attrValue_;

        // pass SAX events
		XmlEvent!T      results_;



		// Code from more complex parser
		double				docVersion_ = 1.0;  // what this document is
		double				parentVersion_ = 0.0;  // if an entity, version of calling document
		double				filterVersion_ = 1.0;  // the resulting filter standard

		// error collection & handling
		XmlErrors   errors_;

		// total  items
		intptr_t			itemCount;
		// version minor
		intptr_t			maxEdition;

        EntityData!T        entity;
        DocTypeData!T		dtd_;
        string[]			systemPaths_;

		XmlContext[]     	contextStack_;
		bool                scopePop;
    }

    alias bool delegate(XmlEvent!T event)  EventDg; // Single delegate for events
    EventDg                                eventDg_;
    bool                                   eventMode_; // results by events

    void setEntityValue(XmlString entityName, XmlString value)
	{
		charEntity[entityName] = value;
	}

    this()
	{
		stateDg_ = &doProlog;
		setEntityValue("lt","<");
		setEntityValue("gt",">");
		setEntityValue("amp","&");
		setEntityValue("quot","\"");
		setEntityValue("apos","\'");
		isNameStartFn = &isNameStartChar10;
		isNameCharFn = &isNameChar10;
		normalizeAttributes_ = true;
		isStandalone_ = true;
		results_ = new XmlEvent!T();
		errors_ = new XmlErrors();

		setXmlVersion(1.0);
	}

	XmlErrors errors() {
        return errors_;
	}

    private final void unpop(dchar makeFront)
    {
        if (backStack.length > 0)
        {
            // already stacked, regardless of source
            if (!empty)
                backStack ~= front;
            front = makeFront;
            empty = false;
            return;
        }
        if (( fpos > 0) && (fpos <= streamData_.length) && (streamData_[fpos-1]==front))
        {
            fpos--;
            front = makeFront;
            empty = false;
            return;
        }
        // out of matching front space
        if (!empty)
            backStack ~= front;
        front = makeFront;
        empty = false;
        return;
    }

    private final void unpop(string s)
    {
        foreach_reverse(char c ; s)
            unpop(c);
    }

    private final void pushBack(dchar c)
    {
        if (!empty)
            backStack ~= front;
        front = c;
        empty = false;
    }
    private final void popFront()
    {
        if (!empty)
        {
            auto bslen = backStack.length;
            if (bslen > 0)
            {
                bslen--;
                front = backStack[bslen];
                backStack.length = bslen;
                return;
            }
            if (fpos >= streamData_.length)
            {
                while (true)
                {
                    if (inputDg_ && inputDg_(streamData_))
                    {
                        fpos = 0;
                        break;
                    }
                    else {
                        streamData_ = null;
                    }
                    if ((contextStack_.length > 0) && !this.scopePop)
                    {
                        popContext();
                        if (!empty)
                            return; // front was previously accounted for.
                        else
                            continue;
                    }
                    empty = true;
                    return;
                }
            }
            front = streamData_[fpos++];
            if (doFilter_ != CharFilter.filterOn)
                lineChar_++;
            else
                filterFront();
            return;
        }
    }
    private final void filterFront()
    {
        immutable c = front;
        if (isEndOfLine_)
        {
            isEndOfLine_ = false;
            lineNumber_++;
            lineChar_ = 0;
            if (lastChar_ == 0x0D)
            {	// filter 0x0D, XXXX combinations
                lastChar_ = 0;
                if (c==0x0A)
                {
                    popFront();
                    return;
                }
                else if (minVersion11_)
                {
                    if (c==0x85)
                    {
                        popFront();
                        return;
                    }
                    else if (c==0x2028)
                    {
                        front = 0x0A;
                        return;
                    }
                }
            }
            lastChar_ = 0;
        }
        if ((c >= 0x20) && (c < 0x7F))
        {
            lineChar_++;
            return;
        }
        else
        { // detect endOfLine or crazy characters
            switch(c)
            {
                case 0x0D:
                    lastChar_ = 0x0D;
                    front = 0x0A;
                    goto case 0x0A;
                case 0x0A:
                    isEndOfLine_ = true;
                    break;
                case 0x09:
                    lineChar_++;
                    break;
                case 0x0085:
                case 0x2028:
                    if (minVersion11_)
                    {
                        lastChar_ = c;
                        front = 0x0A;
                        isEndOfLine_ = true;
                    }
                    else
                    {
                        lineChar_++;
                    }
                    break;
                default:
                    // already approved 0x9, 0xA, 0xD,  0x20 - 0x7F, 0x85
                    immutable isSourceCharacter
                        =   (c <= 0xD7FF)
                        ?  (c > 0x9F) || ((filterVersion_==1) && (c >= 0x20))
                        : ((c >= 0xE000) && (c <= 0xFFFD)) || ((c >= 0x10000) && (c <= 0x10FFFF)) ;


                    if (!isSourceCharacter)
                    {
                        auto severity = XmlErrorLevel.FATAL;
                        // Check position for crappy check for conformance tests on invalid BOM characters.
                        if (lineChar_ == 0 && lineNumber_ == 0)
                            switch(front)
                            {
                                case 0xFFFE:
                                case 0xFEFF:
                                    severity = XmlErrorLevel.ERROR;
                                    goto default;
                                default:
                                    break;
                            }
                        throw errors_.makeException(badCharMsg(front),severity);
                    }
                    lineChar_++;
                    break;
            }

        }
    }
    private final void frontFilterOn()
    {
        if ((doFilter_ != CharFilter.filterOff) || empty)
            return;
        if (lineChar_ != 0)
            lineChar_--; // filter front will increment for current front
        doFilter_ = CharFilter.filterOn;
        filterFront();
    }

        /// stop any calls to frontFilterOn and frontFilterOff from working. Always off
    private final void filterAlwaysOff()
    {
        doFilter_ = CharFilter.filterAlwaysOff;
    }

    /// Turn the filter off
    private final void frontFilterOff()
    {
        if (doFilter_ != CharFilter.filterAlwaysOff)
            doFilter_ = CharFilter.filterOff;
    }

    final uint munchSpace()
    {
        int   count = 0;
        while(!empty)
        {
            switch(front)
            {
                case 0x20:
                case 0x0A:
                case 0x09:
                case 0x0D: // may be introduced as character reference
                    count++;
                    popFront();
                    break;
                default:
                    return count;
            }
        }
        return 0;
    }

    private final bool matchInput(dchar val)
    {
        if (!empty && front == val)
        {
            popFront();
            return true;
        }
        return false;
    }
    // Eat matching input or restore. can only match if char < 0x80
    private final bool matchInput(string match)
    {
        if (empty)
            return false;
        size_t lastmatch = 0; // track number of matched
        size_t mlen = match.length;
        char[]	bufMatch;
        for( ; lastmatch < mlen; lastmatch++)
        {
            if (empty)
                break;
            if (front != match[lastmatch])
                break;
            bufMatch ~= cast(char)(front & 0x7F);
            popFront();
        }
        if (lastmatch == 0)
            return false;
        else if (lastmatch == mlen)
            return true;
        else
        {
            foreach_reverse(d;bufMatch)
                unpop(d);
            return false;
        }
    }
/// got a '[', check the rest
    private final bool isCDataEnd()
    {
        if (empty || front != ']')
            return false;
        squareDepth--;
        popFront();
        if (empty || front != ']')
        {
            unpop(']');
            squareDepth++;
            return false;
        }
        squareDepth--;
        popFront();
        if (empty || front != '>')
        {
            unpop("]]");
            squareDepth += 2;
            return false;
        }
        markupDepth--;
        popFront();
        return true;
    }
    final void parseAll(XmlEvent!T evt = null)
	{
		//eventMode_ = true;
		if (evt !is null)
			results_ = evt;
		try {
			while(stateDg_ !is null)
			{
				stateDg_();
			}
		}
		catch(XmlError x)
		{
			throw x;
		}
		catch(Exception e)
		{
			throw stageError(e.msg);
		}
	}
    private final string stageString()
	{
		final switch(state_){
			case PState.P_PROLOG:
				return "Prolog";
			case PState.P_INT_DTD:
				return "Internal DTD";
			case PState.P_ELEMENT:
				return "Element";
			case PState.P_END_TAG:
				return "End Tag";
			case PState.P_CONTENT:
				return "Content";
			case PState.P_EPILOG:
				return "Epilog";
			case PState.P_END:
				return "End";
		}
	}
	final XmlError stageError(string msg, XmlErrorLevel level = XmlErrorLevel.FATAL)
	{
		XmlError e = new XmlError(msg, level);
		e.addMsg(format("In parse of %s",stageString()));
		return errors_.delegateError(e);
	}

    Exception makeEmpty()
    {
        return errors_.makeException("Unexpected end to parse source");
    }

    void doDocType() {
        throw errors_.makeException("DOCTYPE not supported");
    }

    void doProlog()
    {
        int spaceCt = 0;
        frontFilterOn();

        while(!empty)
        {
            spaceCt = munchSpace();

            if (empty)
                break;

            if (front == '<')
            {
                markupDepth++;
                frontFilterOff();
                popFront();
                if (empty)
                    throw makeEmpty();
                auto test = front;
                switch(test)
                {
                    case '?':
                        popFront();
                        doProcessingInstruction(spaceCt);
                        break;
                    case '!':
                        popFront();
                        if (matchInput("DOCTYPE"))
                        {
                            doDocType();
                            break;
                        }
                        else if (matchInput("--"))
                        {
                            // valid-sa-038  , but if followed by XML declaration its an error!
                            itemCount++;
                            doCommentContent();
                            break;
                        }
                        else
                            throw errors_.makeException("Illegal in prolog");
                        //goto default;
                    default:
                        if (getXmlName(tag_))
                        {
                            if (!hasDeclaration)
                            {
                                if (validate_)
                                {
                                    errors_.pushError("No xml declaration",XmlErrorLevel.INVALID);
                                }
                            }
                            elementDepth++;
                            stateDg_ = &doContent;
                            doStartTag();
                            return;
                        }
                        else {
                            throw errors_.makeException(badCharMsg(test));
                        }
                        //break;

                } // end switch
                if (!eventMode_)
                    return; // with event
            } // end peek
            else
            {
                throw errors_.makeException("expect xml markup");
            }
            // else?
        } // end while
        throw errors_.makeException("bad xml");
        assert(0);
    }

    final bool isNameStartFifthEdition(dchar test)
    {
        if (docVersion_ == 1.0 && maxEdition >= 5)
        {
            if (!isNameStartChar11(test))
                return false;

            if (validate_)
            {
                errors_.pushError("Name start character only specified by XML 1.0 fifth edition",XmlErrorLevel.INVALID);
                errors_.checkErrorStatus();
            }
            return true;
        }
        return false;
    }
    final bool isNameCharFifthEdition(dchar test)
    {
        if (docVersion_ == 1.0 && maxEdition >= 5)
        {
            if (!isNameChar11(test))
                return false;

            if (validate_)
            {
                errors_.pushError("Name character only specified by XML 1.0 fifth edition",XmlErrorLevel.INVALID);
                errors_.checkErrorStatus();
            }
            return true;
        }
        return false;
    }
    final bool getXmlName(ref XmlString tag)
    {
        if (empty)
            return false;
        auto test = front;
        if ( !(isNameStartFn(test) || isNameStartFifthEdition(test)) )
            return false;

        frontFilterOff();
        sxml!T.reset(bufTag_);
        //bufTag_.shrinkTo(0);
        bufTag_ ~= test;

        popFront();
        while (!empty)
        {
            test = front;
            if (isNameCharFn(test) || isNameCharFifthEdition(test))
            {
                bufTag_ ~= test;
                popFront();
            }
            else
                break;
        }
        //tag = bufTag_.idup;
        tag = sxml!T.data(bufTag_).idup;
        //tag = bufTag_.data.idup;
        frontFilterOn();
        return true;
    }

    final bool getXmlName(ref XmlBuffer ename)
    {
        if (empty)
            return false;
        auto test = front;
        if ( !(isNameStartFn(test) || isNameStartFifthEdition(test)) )
            return false;

        frontFilterOff();
        //ename.length = 0;
        sxml!T.reset(ename);
        //ename.shrinkTo(0);
        ename ~= test;
        popFront();
        while (!empty)
        {
            test = front;
            if (isNameCharFn(test) || isNameCharFifthEdition(test))
            {
                ename ~= test;
                popFront();
            }
            else
                break;
        }
        frontFilterOn();
        return true;
    }

    Exception incompleteTag() {
        throw errors_.makeException("Incomplete Tag");
    }
    private final void doStartTag()
    {
        state_ = PState.P_ELEMENT;
        int attSpaceCt = 0;
        auto attrCount = 0;
        results_.attributes.length = 0;

        //auto prepareAttributes = (evt_.nameEvent.startTagDg_ !is null) || (evt_.nameEvent.soloTagDg_ !is null);
        void setResults(SAX id)
        {
            with(results_)
            {
                eventId = id;
                data = tag_;
            }

            if (eventMode_)
            {
                eventDg_(results_);
            }
        }

        while (true)
        {
            attSpaceCt = munchSpace();

            if (empty)
                throw makeEmpty();

            switch(front)
            {
                case '>': // end of tag,  possible inner content
                    markupDepth--;
                    frontFilterOn();
                    if (elementDepth + stackElementDepth == 1) // very first tag
                    {
                        // delayed popFront,
                        // processing as startTag
                        setResults(SAX.TAG_START);
                        popFront();
                        return;
                    }

                    popFront();

                    if (empty)
                        throw makeEmpty();
                    /* Check for immediate following end tag, which means TAG_EMPTY */
                    if (front == '<')
                    {
                        /*NoneEmptyState nes;
                        getState(nes);*/
                        markupDepth++;

                        // regression ticket 7: popping front here, because want to check if next character is a / using a strict input range
                        // to check the dchar
                        popFront();
                        if (empty)
                            throw makeEmpty();
                        if (front == '/')
                        {
                            // by strict rules of XML, must be the end tag of preceding start tag.
                            popFront();
                            if (empty)
                                throw makeEmpty();
                            if (!getXmlName(attrName_) || (tag_ != attrName_))
                                throw mismatchTag();
                            munchSpace(); // possible space after end tag name!
                            if (empty || (front != '>'))
                                throw missingEndBracket();
                            markupDepth--;
                            elementDepth--; // cancel earlier increment
                            popFront();
                            setResults(SAX.TAG_EMPTY);
                            checkEndElement();
                            itemCount++;
                            return;
                        }
                        else
                        {
                            markupDepth--;
                            unpop('<');
                            setResults(SAX.TAG_START);
                        }
                        return;
                    }
                    itemCount++;
                    setResults(SAX.TAG_START);
                    return;
                case '/':
                    popFront();
                    if (empty)
                        throw makeEmpty();
                    if (front != '>')
                        throw incompleteTag();

                    markupDepth--;
                    elementDepth--;
                    frontFilterOn();
                    popFront();
                    setResults(SAX.TAG_EMPTY);
                    checkEndElement();
                    itemCount++;
                    return;

                default:
                    // processs another attribute
                    if (attSpaceCt == 0 && !isHTML_)
                    {
                        throw missingSpace();
                    }
                    if (!getXmlName(attrName_))
                    {
                        errors_.pushError("Missing attribute value",XmlErrorLevel.INVALID);
                        throw errors_.makeException(badCharMsg(front));
                    }

                    if (attSpaceCt == 0)
                        throw missingSpace();

                    getAttributeValue(attrValue_);


                    if (normalizeAttributes_)
                    {
                        attributeNormalize(attrValue_);

                        if (attrName_ == "xml:space")
                        {
                            if (attrValue_ == "preserve")
                            {

                            }
                            else if (attrValue_ == "default")
                            {

                            }
                            else
                            {
                                errors_.makeException("xml:space must equal 'preserve' or 'default'",XmlErrorLevel.ERROR);
                            }
                        }
                        /// TODO: actually implement space instructions?
                    }
                    results_.attributes.push( attrName_,attrValue_ );

                    attrCount += 1;
                    break;
            }
        }
        assert(0);
    }

    void returnTextContent()
    {
        // encountered non-content character, return content block
        itemCount++;
        with(results_)
        {
            eventId = SAX.TEXT;
                //data = bufContent_.data.idup;
            data = sxml!T.data(bufContent_).idup;
            attributes.length = 0;
        }
        if (eventMode_) {
            eventDg_(results_);
        }
        //bufContent_.length = 0;
        sxml!T.reset(bufContent_);
        //bufContent_.shrinkTo(0);
        inCharData = false;
        return;
    }

    string unknownEntityMsg(const(T)[] ename)
    {
        return format("Unknown Entity %s",ename);
    }

    Exception badEntityReference() {
        return errors_.makeException("Expected entity reference");
    }
    Exception missingQuote() {
        return errors_.makeException("Missing quote character");
    }

    Exception missingSpace() {
        return errors_.makeException("Missing space character");
    }

    Exception missingValue() {
        return errors_.makeException("Missing attribute value");
    }

    enum missingEndTag = "Missing end >";
    Exception missingEndBracket() {
        return errors_.makeException(missingEndTag);
    }

    Exception mismatchTag() {
        return errors_.makeException("Element nesting error");
    }

    final void checkEndElement()
    {
        int depth =  elementDepth + stackElementDepth;
        if (isHTML_)
        {
            // anything goes

        }
        else {
            if (depth < 0)
                throw mismatchTag();
            else if (depth == 0)
            {
                stateDg_ = &doEpilog;
                state_ = PState.P_EPILOG;
            }
            else {
                state_ = PState.P_CONTENT;
            }
            if (elementDepth < 0)
                throw mismatchTag();
        }
    }

    final void doEndTag()
    {
        state_ = PState.P_END_TAG;
        dchar  test;
        if (getXmlName(tag_))
        {
            // has to be end
            munchSpace();
            if (empty || front != '>')
                throw missingEndBracket();
            markupDepth--;
            elementDepth--;
            popFront();
            checkEndElement();
            itemCount++;
            with(results_)
            {
                eventId = SAX.TAG_END;
                data = tag_;
                attributes.length = 0;
            }
            if (eventMode_) {
                eventDg_(results_);
            }

            return;
        }
        throw errors_.makeException("end tag expected");
    }

    final void doContent()
    {
        state_ = PState.P_CONTENT;
        //bufContent_.shrinkTo(0);
        sxml!T.reset(bufContent_);
        inCharData = false;
        frontFilterOn();
        LOOP_FOREVER:
        while (true)
        {	// loop until something new occurs
            if (empty)
            {
                if (elementDepth + stackElementDepth > 0)
                    throw makeEmpty();
                if (inCharData)
                    returnTextContent();
                return;
            }
            if (front == '<')
            {
                if (inCharData)
                {
                    returnTextContent();
                    if (!eventMode_)
                        return;
                }
                markupDepth++;
                frontFilterOff();
                popFront();
                if (empty)
                    throw makeEmpty();
                auto test = front;
                switch(test)
                {
                    case '/':
                        popFront();
                        doEndTag();
                        if (state_ == PState.P_EPILOG)
                            return;
                        break;
                    case '?':
                        popFront();
                        doProcessingInstruction();
                        break;
                    case '!': // comment or cdata
                        popFront();
                        doBang();
                        break;
                    default:
                        // no pop front
                        if (getXmlName(tag_))
                        {
                            elementDepth++;
                            doStartTag();
                            state_ = PState.P_CONTENT;
                            break;
                        }
                        else
                        {
                            /// trick conformance issue
                            errors_.pushError(missingEndTag, XmlErrorLevel.FATAL);
                            throw errors_.makeException(badCharMsg(test));
                        }
                } // end switch
                if (eventMode_)
                    continue LOOP_FOREVER;
                else
                    return;
            }
            else if (front=='&')
            {
                // Cannot determine content in advance. Invalidates content so far, ? return text so far?
                popFront();
                if (!empty)
                {
                    uint radix;
                    if (front == '#')
                    {
                        dchar test = expectedCharRef(radix);
                        bufContent_ ~= test;
                        inCharData = true;
                        continue;
                    }
                    else if (getXmlName(tag_))
                    {
                        if (empty || front != ';')
                            throw badEntityReference();
                        popFront();
                        auto pc = tag_ in charEntity;
                        if (pc !is null)
                        {
                            bufContent_ ~= *pc;
                            inCharData = true;
                            continue;
                        }
                        // there's no dtd entity in this version
                        throw errors_.makeException(unknownEntityMsg(tag_));

                    }
                }
                errors_.makeException("expected entity");
            }
            else
            {
                if (!inCharData)
                {
                    inCharData = true;
                    sxml!T.reset(bufContent_);
                }
                bufContent_ ~= front;
                final switch(bbct)
                {
                case BBCount.b1:
                    if (front==']') bbct = BBCount.b2;
                    break;
                case BBCount.b2:
                    bbct = (front==']') ? BBCount.bend : BBCount.b1;
                    break;
                case BBCount.bend:
                    if (front=='>')
                        throw errors_.makeException("illegal CDATA end ]]>");
                    bbct = (front==']') ? BBCount.bend : BBCount.b1;
                    break;
                }

                popFront();

            } // end switch
        } // While not epilog
    }
    // After getting '<!--' leave in bufContent_
    final void parseComment()
    {
        dchar  test  = 0;
        //bufContent_.shrinkTo(0);
        sxml!T.reset(bufContent_);
        frontFilterOn();
        while(!empty)
        {
            if (front=='-')
            {
                popFront();
                if (empty)
                    break;
                if (front=='-')
                {
                    popFront();
                    if (empty)
                        break;
                    if(front != '>')
                        throw errors_.makeException("Comment must not contain --");
                    markupDepth--;
                    popFront();
                    return;
                }
                bufContent_ ~= '-';
                continue;
            }
            bufContent_ ~= front;
            popFront();
        }
        throw errors_.makeException("Unterminated comment");
    }

    final void doCommentContent()
    {
        parseComment();
        with(results_)
        {
            eventId = SAX.COMMENT;
            data = sxml!T.data(bufContent_).idup;
                //bufContent_.data.idup;
            results_.attributes.length = 0;
        }
        if (eventMode_) {
            eventDg_(results_);
        }
        sxml!T.reset(bufContent_);
    }

    void setXmlVersion(double value)
    {
        if ((value != 1.0) && (value != 1.1))
        {
            uint major = cast(uint) value;
            if (major != 1 || maxEdition < 5)
                throw errors_.makeException(format("XML version %s not supported ",value),XmlErrorLevel.ERROR);
        }
        docVersion_ = value;
        if (isEntity)
        {
            if (docVersion_ > parentVersion_)
                throw errors_.makeException(format("Entity version %s > Document version %s", docVersion_, parentVersion_), XmlErrorLevel.FATAL);
            filterVersion_ = parentVersion_;
        }
        else
            filterVersion_ = docVersion_;

        minVersion11_ = (filterVersion_ > 1.0);

        if (minVersion11_)
        {
            isNameStartFn = &isNameStartChar11;
            isNameCharFn = &isNameChar11;
        }
    }

    void doProcessingInstruction(uint spaceCt = 0)
    {
        immutable(T)[] target;

        if (!getXmlName(target))
            throw errors_.makeException("Bad processing instruction name");

        if (namespaceAware_ && (indexOf(target,':') >= 0))
            throw errors_.makeException(format(": in process instruction name %s for namespace aware parse",target));

        if (target == "xml")
        {
            Exception badThrow = null;

            if (inDTD_)
                throw errors_.makeException("Xml declaration may not be in DTD");
            if (state_ > PState.P_PROLOG || (spaceCt > 0) || (itemCount > 0))
                throw errors_.makeException("xml declaration should be first");

            if (!hasDeclaration)
            {
                hasDeclaration = true;

                /*try
                {*/
                    doXmlDeclaration();
                    munchSpace();
                    return;
                /*}
                catch (XmlError xm)
                {
                    auto s = xm.toString();
                    badThrow = errors_.preThrow(new XmlError(s, xm.level));
                }
                catch (Exception ex)
                {
                    badThrow = errors_.preThrow(new XmlError(ex.msg));
                }*/
            }
            else
                badThrow = errors_.makeException("Duplicate xml declaration");

            if (badThrow !is null)
                throw badThrow;
        }
        auto lcase = target.toLower();

        if (lcase == "xml")
        {
            throw errors_.makeException(format("%s is invalid name", target));
        }

        getPIData(bufContent_);

            //XmlEvent!T	results_;
        with (results_)
        {
            eventId = SAX.XML_PI;
            data = target;
            attributes.push(target,sxml!T.data(bufContent_).idup);
        }
        if(eventMode_) {
            eventDg_(results_);
        }

        itemCount++;
        if (state_ == PState.P_PROLOG)
            munchSpace();
    }

    final void doEpilog()
    {
        dchar test = 0;
        string content;

        LOOP_FOREVER:
        while(!empty)
        {
            munchSpace();
            if (empty)
                break;
            if (front != '<')
            {
                throw errors_.makeException("illegal data at end document");
            }

            markupDepth++;

            popFront();
            if (empty)
                throw errors_.makeException("unmatched markup");
            switch(front)
            {
                case '?': // processing instruction or xmldecl
                    popFront();
                    doProcessingInstruction(); // what else to do with PI'S?
                    break;
                    //break LOOP_FOREVER;
                case '!':
                    if (empty)
                        throw makeEmpty();
                    popFront();
                    if (matchInput("--"))
                    {
                        doCommentContent();
                        break;
                    }
                    goto default;
                default:
                    if (getXmlName(bufTag_))
                        throw errors_.makeException(format("Epilog illegal %s",sxml!T.data(bufTag_)),XmlErrorLevel.FATAL);
                    else
                        throw errors_.makeException("Epilog illegal " ~ badCharMsg(front));
            }
        }
        with (results_)
        {
            eventId = SAX.DOC_END;
            data = null;
            attributes.length = 0;
        }
        state_ = PState.P_END;
        stateDg_ = null;
    }

    Exception cdataOrComment() {
        return errors_.makeException("Expected CDATA or Comment");
    }

    final void doBang()
    {
        if (matchInput("[CDATA["))
        {
            squareDepth += 2;
            doCDATAContent();
            return;
        }
        else if (matchInput("--"))
        {
            doCommentContent();
            return;
        }
        throw cdataOrComment();
    }

    final void doCDATAContent()
    {
        sxml!T.reset(bufContent_);
        frontFilterOn();
        while(!empty)
        {
            if ((front == ']') && isCDataEnd())
            {
                itemCount++;
                with(results_)
                {
                    eventId = SAX.CDATA;
                    data = sxml!T.data(bufContent_).idup;
                    attributes.length = 0;
                }
                if (eventMode_) {
                    eventDg_(results_);
                }
                sxml!T.reset(bufContent_);
                return;
            }
            else
            {
                bufContent_ ~= front;
                popFront();
            }
        }
        throw makeEmpty();
    }

    final void getAttributeValue(ref immutable(T)[] val)
    {
        munchSpace();
        dchar test;
        if (empty || (front != '='))
            throw missingValue();
        popFront();
        munchSpace();
        unquoteValue(val);
    }
    final void unquoteValue(ref XmlString val)
    {
        dchar enquote = (empty ? 0x00 : front);
        bool  deviant = false;

        if ((enquote == '\'') || (enquote == '\"'))
        {
            popFront();
        }
        else if (!isHTML_)
            throw missingQuote();

        //bufAttr_.length = 0;
        //bufAttr_.shrinkTo(0);
        sxml!T.reset(bufAttr_);
        frontFilterOn(); // ackward character rules?
        while(!empty)
        {
            if (front == enquote)
            {
                if (sxml!T.length(bufAttr_) > 0)
                {
                    val = sxml!T.data(bufAttr_).idup;
                }
                else
                    val = [];
                frontFilterOff();
                popFront();
                return;
            }
            else
            {
                if (lastChar_)
                    deviant = true;

                if (isHTML_ && (enquote==0x00))
                {
                    // HTML is slack, and I don't know the spec
                    if ((front != '/') && (front != '>') &&
                        !isSpace(front))
                    {
                        bufAttr_ ~= front;
                    }
                    else {
                        frontFilterOff();
                        return;  // NO pop
                    }
                }
                else {
                    bufAttr_ ~= front;
                }
                popFront();
            }
        }
        throw missingQuote();
    }

    void attributeNormalize(ref immutable(T)[] src)
    {
        //TODO: any other standard entities not allowed either?
        void noLTChar()
        {
            throw errors_.makeException("< not allowed in attribute value");
        }

        void noSingleAmp()
        {
			throw errors_.makeException("single '&' not allowed");
        }

		intptr_t   epos = -1;
	ENTITY_SCAN:
		for(auto ix = 0; ix < src.length; ix++)
		{
			switch(src[ix])
			{
				case '<':
					noLTChar();
					break;
				case '&':
					epos = ix;
					break ENTITY_SCAN;
				default:
					break;
			}
		}
		if (epos < 0)
		{
			// no entities
			return;
		}
		sxml!T.assign(bufNormAttr_, src[0..epos]);
        pushContext(src[epos..$], true, null);
        scope(exit)
            popContext();

        SCAN:
		while(!empty)
        {
			immutable test = front;
			switch(test)
			{
			case 0x20:
			case 0x0D:
			case 0x0A:
			case 0x09:
				bufNormAttr_ ~= ' ';
                popFront();
                continue SCAN;
			case '<':
				noLTChar();
				break;
			case '&':
                popFront();
                if (empty)
                    noSingleAmp();
                if (front == '#')
                {
                    uint radix;
                    dchar cref = expectedCharRef(radix);
                    bufNormAttr_ ~= cref;
                    continue;
                }
				XmlString entityName;
                if (!getXmlName(entityName) || !matchInput(';'))
                    noSingleAmp();
                auto pc = entityName in charEntity;
                if (pc is null)
                {
                    pushEntity(entityName, true);
                }
                else
                {
                    bufNormAttr_ ~= *pc;
                }
				break;
			default:
                bufNormAttr_ ~= front;
                popFront();
				break;
            }
        }
		src = sxml!T.data(bufNormAttr_).idup;
    }

    final dchar expectedCharRef(ref uint radix)
    {
        if (empty)
            throw makeEmpty();
        if (front != '#')
            throw errors_.makeException(badCharMsg(front));
        popFront();
        dchar result;
        radix = refToChar(result);

        if (
            ((docVersion_ < 1.1) && !isChar10(result)) ||
            (!isChar11(result) && !isControlCharRef11(result))
        )
        {
            throw errors_.makeException(badCharMsg(front));
        }
        return result;
    }

    /// Return value is the radix of the encoding for the character
    /// Throws exception for invalid encoding
    final uint refToChar(ref dchar c)
    {
        dchar test;
        int digits = 0;
        uint radix = 10;

        if (empty)
            throw makeEmpty();

        test = front;

        if (test == 'x')
        {
            popFront();

            radix = 16;
            if (empty)
                throw badEntityReference();
            test = front;
        }
        int 	n = 0;
        ulong	value = 0; // 64 bits, detect 32 bit overflow

        while(test == '0')
        {
            popFront();
            if (empty)
                throw badEntityReference();
            test = front;
        }
        if (radix == 10)
        {
            while(true)
            {
                if (( test >= '0') && ( test <= '9'))
                {
                    n = (test - '0');
                    value *= 10;
                    value += n;
                    digits++;
                }
                else
                    break; // not part of number

                popFront();
                if (empty)
                    throw badEntityReference();
                if (value > 0x10FFFF)
                    throw badEntityReference();
                test = front;
            }
        }
        else
        {
            while(true)
            {
                if (( test <= '9') && (test >= '0'))
                    n = (test - '0');
                else if ((test <= 'F') && (test >= 'A'))
                    n = (test - 'A') + 10;
                else if ((test <= 'f') && (test >= 'a'))
                    n = (test - 'a') + 10;
                else
                    break;// not part of number
                digits++;
                value *= 16;
                value += n;

                popFront();
                if (empty)
                    throw badEntityReference();
                if (value > 0x10FFFF)
                    throw badEntityReference();
                test =  front;
            }
        }
        if (test != ';')
        {
            throw badEntityReference();
        }
        popFront();
        c = cast(dchar) value;
        return radix;
    }

    void doXmlDeclaration()
    {
        double xml_value = 1.0;
        immutable(T)[] xmlStrValue;
        immutable(T)[] encodingValue;
        immutable(T)[] standaloneValue;

        //state_ = XML_DECLARATION;
        int spaceCt =  munchSpace();
        size_t atcount = 0;
        isStandalone_ = false; // if has an xml declaration, assume false as default
        //string atname;
        //string atvalue;

        void xmlVersionFirst(bool force=false)
        {
            if (!isEntity || force)
                errors_.pushError("xml version must be first",XmlErrorLevel.FATAL);
        }

        void xmlDuplicate(const(T)[] s)
        {
            errors_.pushError(format("duplicate %s", s),XmlErrorLevel.FATAL);
        }
        void xmlStandaloneLast()
        {
            errors_.pushError("xml standalone must be last",XmlErrorLevel.FATAL);
        }


        // get the values before processing

        while(!matchInput("?>"))
        {
            if (!getXmlName(attrName_))
            {
                //throwNotWellFormed("declaration attribute expected");
                // got a strange character?
                if (empty)
                    throw makeEmpty();
                dchar badChar = front;
                //Extreme focus on XML declaration conformance errors.
                switch(badChar)
                {
                    case '>':
                    case '<':
                        throw errors_.makeException("expected ?>");
                        //break;
                    case '\'':
                    case '\"':
                        throw errors_.makeException("expected attribute name");
                        //break;
                    case 0x85:
                    case 0x2028:
                        if (xml_value == 1.1)
                        {
                            errors_.pushError(format("%x illegal in declaration", badChar),XmlErrorLevel.ERROR);
                            errors_.checkErrorStatus();
                        }
                        goto default;
                    default:
                        throw errors_.makeException(badCharMsg( badChar));
                }
            }


            if  (!spaceCt)
                throw errors_.makeException("missing spaces");

            getAttributeValue(attrValue_);
            if (attrName_.length==0)
                throw errors_.makeException("empty declaration value");

            atcount += 1;

            switch(attrName_)
            {
                case "version":
                    if (hasXmlVersion)
                    {
                        xmlDuplicate(attrName_);
                        break;
                    }
                    if (hasStandalone || hasEncoding)
                        xmlVersionFirst(true);
                    hasXmlVersion = true;
                    xmlStrValue = attrValue_;
                    xml_value = doXmlVersion(xmlStrValue);
                    break;
                case "encoding":
                    if (!hasXmlVersion)
                        xmlVersionFirst();
                    if (hasStandalone)
                        xmlStandaloneLast();
                    if (hasEncoding)
                    {
                        xmlDuplicate(attrName_);
                        break;
                    }
                    encodingValue = to!(immutable(T)[]) (attrValue_);
                    hasEncoding = true;
                    break;
                case "standalone":
                    if (isEntity)
                        throw errors_.makeException("standalone illegal in external entity");
                    if (!hasXmlVersion)
                        xmlVersionFirst();
                    if (hasStandalone)
                    {
                        xmlDuplicate(attrName_);
                        break;
                    }
                    standaloneValue = attrValue_;
                    hasStandalone = true;
                    break;
                default:
                    throw errors_.makeException(format("unknown declaration attribute %s ", attrName_));
                    //break;
            }
            spaceCt = munchSpace();
        }
        results_.attributes.reset();

        if (hasXmlVersion)
        {
            setXmlVersion(xml_value);
            results_.attributes.push("version",xmlStrValue);
        }
        markupDepth--;
        if (isEntity && !hasEncoding)
            throw errors_.makeException("Optional entity text declaration must have encoding=");
        errors_.checkErrorStatus();

        if (hasEncoding)
        {
            setXmlEncoding(encodingValue);
            results_.attributes.push("encoding", encodingValue);
        }
        if (hasStandalone)
        {
            setXmlStandalone(standaloneValue);
            results_.attributes.push("standalone", standaloneValue);
        }
        // send event
        with(results_)
        {
            eventId = SAX.XML_DEC;
            data = "xml";
        }
        if (eventMode_ && eventDg_) {
            eventDg_(results_);
        }

        //TODO: Event call
        state_ = PState.P_ELEMENT;
        stateDg_ = &doContent;
        itemCount++;
    }

    final void getPIData(ref XmlBuffer app)
    {
        dchar  test  = 0;

        bool	hasContent = false;
        bool	hasSpace = false;

        sxml!T.reset(app);

        frontFilterOn();
        while(!empty)
        {
            test = front;
            popFront();
            if (test=='?')
            {
                if (!empty && front=='>')
                {
                    markupDepth--;
                    popFront();
                    break;
                }
            }
            if (!hasContent)
            {
                if (isSpace(test))
                    hasSpace = true;
                else
                {
                    hasContent = true;
                    app ~= test;
                }
            }
            else
                app ~= test;
        }
        if (hasContent && !hasSpace)
            throw errors_.makeException("Processing instruction needs space after name");
    }
/// push a new context, for parse, maybe with EntityData
    void pushContext()
	{
		auto cix = contextStack_.length;
		contextStack_.length = cix + 1;

		XmlContext* ctx_ = &contextStack_[cix];

		ctx_.markupDepth = markupDepth;
		ctx_.elementDepth = elementDepth;
		ctx_.squareDepth = squareDepth;
		ctx_.parenDepth = parenDepth;
		ctx_.docDeclare = docDeclare;
		ctx_.inputDg_ = inputDg_;

		ctx_.front = front;
		ctx_.empty = empty;
		ctx_.docVersion_ = docVersion_;

		ctx_.streamData = streamData_;
		ctx_.fpos = fpos;

		ctx_.entity = entity;
		ctx_.scopePop = scopePop;
		ctx_.lineNumber_ = lineNumber_;
		ctx_.lineChar_ = lineChar_;
		ctx_.lastChar_ = lastChar_;
		ctx_.isEndOfLine_ = isEndOfLine_;
		ctx_.minVersion11_ = minVersion11_;

		ctx_.doFilter_ = doFilter_;

		// setup new defaults
		lineNumber_ = 0;
		lineChar_ = 0;
		lastChar_ = 0;
		isEndOfLine_ = false;

		fpos = 0;

		streamData_ = null;
        inputDg_ = null;

        markupDepth = 0;
		stackElementDepth += elementDepth;
        elementDepth = 0;
        squareDepth = 0;
        parenDepth = 0;
		docDeclare = 0;
		// doFilter_ retains value
		backStack = [];
		empty = false;
		// force new front
	}

    // push an entire source array
    void pushContext(immutable(T)[] data, bool inScope = true, EntityData!T edata = null)
	{
		pushContext();
		entity = edata;
		scopePop = inScope;

		if (inScope || edata !is null)
            filterAlwaysOff();

		initSource(data);
	}


    bool pushEntity(const(T)[] ename, bool isAttribute)
    {
        EntityData!T ed = getEntityData(ename, isAttribute);

        if (ed !is null)
        {
            auto evalue = ed.value_;
            if (evalue.length > 0)
			{
				//frontFilterOff();
                pushContext(evalue,false,ed);
			}
			return true;
        }
		else
			errors_.checkErrorStatus();
		return false;
    }
    void popContext()
    {
		if (!scopePop)
			checkBalanced();
        auto slen = contextStack_.length;
        if (slen > 0)
        {
            slen--;
			auto ctx_ = contextStack_[slen];

			markupDepth += ctx_.markupDepth;
			elementDepth += ctx_.elementDepth;
			squareDepth += ctx_.squareDepth;
			parenDepth += ctx_.parenDepth;

			if (inParamEntity)
			{
				docDeclare += ctx_.docDeclare;
			}
			else {
				stackElementDepth -= elementDepth;
			}

			inputDg_ = ctx_.inputDg_;

			front = ctx_.front;
			empty = ctx_.empty;
			docVersion_ = ctx_.docVersion_;

			streamData_ = ctx_.streamData;
			fpos = ctx_.fpos;
			entity = ctx_.entity;
			scopePop = ctx_.scopePop;
			lineNumber_ = ctx_.lineNumber_;
			lineChar_ = ctx_.lineChar_;
			lastChar_ = ctx_.lastChar_;
			isEndOfLine_ = ctx_.isEndOfLine_;
			minVersion11_ = ctx_.minVersion11_;

			doFilter_ = ctx_.doFilter_;
			contextStack_.length = slen;
        }
		if (slen==0)
			stackElementDepth = 0;
    }


    double doXmlVersion(const(T)[] xmlversion)
    {
        T[]  scratch;

        NumberClass nc = parseNumber(ReadRange!T(xmlversion), scratch);

        //auto vstr = scratch_.toArray;
        if (nc != NumberClass.NUM_REAL)
            throw errors_.makeException(format("xml version %s weird ",xmlversion));
        if (scratch.length < xmlversion.length)
            throw errors_.makeException("additional text in xml version");
        return  to!double(scratch);
    }

    void setXmlEncoding(const(T)[] encoding)
    {
        bool encodingOK = (encoding.length > 0) && isAlphabetChar(encoding[0]);
        if (encodingOK)
        {
            encodingOK = isAsciiName!(const(T)[])(encoding);
        }
        if (!encodingOK)
        {
            throw errors_.makeException(format("Bad encoding name: %s", encoding));
        }
        // prepare to fail low level
        try
        {
            // encoding stuff in dchar ?
            // errors_.setEncoding(encoding);
            xmlEncoding_ = to!string(encoding);
            if (fillSource_ !is null)
                fillSource_.setEncoding(xmlEncoding_);
        }
        catch (XmlError ex)
        {
            // defer
            switch(ex.level)
            {
                case XmlErrorLevel.INVALID:
                    // convert to report and carry on
                    if (validate_)
                    {
                        errors_.pushError(ex.toString(),XmlErrorLevel.INVALID);
                    }
                    break; // ignore
                case XmlErrorLevel.ERROR:
                    errors_.pushError(ex.toString(),XmlErrorLevel.ERROR);
                    break;
                case XmlErrorLevel.FATAL:
                default:
                    errors_.pushError(ex.toString(),XmlErrorLevel.FATAL);
            }
        }
        catch(Exception ex)
        {
            errors_.pushError(ex.toString(),XmlErrorLevel.FATAL);
        }
        errors_.checkErrorStatus();
        if (fillSource_ !is null) {
            fillSource_.setBufferSize(1024);
        }
    }
    void setXmlStandalone(const(T)[] standalone)
    {
        if (standalone == "yes")
            isStandalone_ = true;
        else if (standalone == "no")
            isStandalone_ = false;
        else
            throw errors_.makeException(format("Bad standalone value: %s",standalone));
    }
	final void initSource(immutable(T)[] src)
	{
		streamData_ = to!(immutable(dchar)[])(src);
		fpos = 0;
		empty = (streamData_.length==0);
		popFront();
	}
	final void initSource(MoreInputDg dg)
	{
		inputDg_ = dg;
		empty = false;
		popFront();
	}

    Exception makeUnknownEntity(const(T)[] dname)
    {
        auto s = unknownEntityMsg(dname);
        auto level = inParamEntity()  ? XmlErrorLevel.ERROR : XmlErrorLevel.FATAL;
        return errors_.makeException(s,level);
    }

    EntityData!T getEntityData(const(T)[] dname, bool isAttribute)
    {
        if (dtd_ is null)
            throw makeUnknownEntity(dname);

        auto ge = dtd_.getEntity(dname);

        if (ge is null)
        {
            if (dtd_.undeclaredInvalid_ && !isAttribute)
            {
                if (validate_ )
                {
                    errors_.pushError(format("referenced undeclared entity %s", dname),XmlErrorLevel.INVALID);
                    errors_.checkErrorStatus();
                }
                return null;
            }
            else
                throw makeUnknownEntity(dname);
        }
        if (ge.status_ == EntityData!T.Expanded)
            return ge;

		if (isAttribute)
			if (ge.src_.systemId_.length > 0)
				throw errors_.makeException("Entity with System reference in attribute");
        StringSet!T eset;

        int reftype = RefTagType.UNKNOWN_REF;
		if (! deriveEntityContent(ge, eset, reftype))
            return null;
		/*
        if (!lookupReference(ge.name_, eset, value, reftype))
        {
            doNotWellFormed(text("Error in entity lookup: ", ge.name_));
        }
		*/

        if (reftype==RefTagType.NOTATION_REF)
        {
            throw errors_.makeException(text("Reference to unparsed entity ",dname));
        }
        /*if(isAttribute && this.isStandalone_ && reftype==RefTagType.SYSTEM_REF)
            throw errors_.makeException("External entity in attribute of standalone document");*/

        return ge;
	}
    bool validate() const @property
    {
        return validate_;
    }
    void validate(bool val) @property
    {
        validate_ = val;
    }

	bool isStandalone() const @property
    {
        return isStandalone_;
    }

    bool  inParamEntity() const @property
    {
        return (entity !is null) && (entity.etype_ == EntityType.Parameter);
    }

    ///  IXMLParser method, may not actually be used
    bool inGeneralEntity() const @property
    {
        return (entity !is null) && (entity.etype_ == EntityType.General);
    }

    final void checkBalanced()
    {
		char[]	msg;

		auto balanceMismatchMsg()
		{
			msg.length = 0;
			if (squareDepth != 0)
				msg ~= "Mismatch of [ ] ";
			if (markupDepth != 0)
				msg ~= "Mismatch of < > ";
			if (elementDepth != 0)
				msg ~= "Mismatch of element depth ";
			if (parenDepth != 0)
				msg ~= "Mismatch of ( ) ";
			return msg;
		}

        if ((squareDepth != 0) || (markupDepth != 0) || (elementDepth != 0) || (parenDepth != 0))
        {
            if (!inParamEntity)
            {
                // do not understand the difference between xmltest\invalid--005 and not-wf-not-sa-009
				if ((markupDepth > 0) || (elementDepth > 0))
					throw errors_.makeException(text("Imbalance on end context: ", balanceMismatchMsg()));
            }
            else
            {
				if (docDeclare > 0)
					throw errors_.makeException("Parameter entity with incomplete declaration");

                if (elementDepth != 0)
                {
                    throw errors_.makeException("unbalanced element in entity content");
                }
                else if ((squareDepth==0) && (parenDepth != 0))
                {
                    if (validate_)
                        errors_.pushError("parenthesis mismatch across content source",XmlErrorLevel.INVALID);
                }
                else if (validate_)
                    errors_.pushError(text("Bad content nesting in entity ",balanceMismatchMsg()),XmlErrorLevel.INVALID);

			}
        }
    }

    private bool deriveEntityContent(EntityData!T entity, StringSet!T stk, out int reftype)
    {

        if (isStandalone())
        {
            if (!entity.isInternal_) // w3c test sun  not-wf-sa03
            {
                errors_.pushError("Standalone yes and referenced external entity",XmlErrorLevel.FATAL);
                return false;
            }

        }
        if (entity.status_ == EntityData!T.Expanded)
        {
            reftype = entity.reftype_;
            return true;
        }
        if (entity.status_ < EntityData!T.Found)
        {
            if (entity.ndataref_.length > 0) // get the notation
            {
                reftype = RefTagType.NOTATION_REF;
                //auto nmap = docTypeNode_.getNotations();
				// auto n = nmap.getNamedItem(entity.ndataref_);
				auto n = dtd_.notationMap.get(entity.ndataref_,null);

                if (n is null)
                {
                    if (validate())
                        errors_.pushError(text("Notation not declared: ", entity.ndataref_),XmlErrorLevel.INVALID);
                    entity.status_ = EntityData!T.Failed;
                    return true; // need to check replaced flag!
                }
                else
                {
                    // TODO: what do do with notations?
                    entity.status_ = EntityData!T.Expanded;
                    return true;
                }
            }
            else if (entity.src_.systemId_ !is null)
            {
                     //Document doc = new Document();
				reftype = RefTagType.SYSTEM_REF;

                if (entity.src_.systemId_.length > 0) // and not resolved?
                {
					if (!readSystemEntity(entity))
						return false;
                }
                else
                {
                    errors_.pushError("DTD SYSTEM uri missing",XmlErrorLevel.ERROR);
                    return false;
                }
            }
            else
            {
				entity.status_ = EntityData!T.Expanded;
				entity.value_ = null;
				return true;
            }
        }
        // for checking well formed for standalone=yes,
        // need to fail if the original entity was internal

        if (entity.status_ == EntityData!T.Found) // can be empty!
        {
            if (!stk.put(entity.name_))
            {
                reftype = RefTagType.ENTITY_REF;
                errors_.pushError(text("recursion in entity lookup for ", entity.name_),XmlErrorLevel.ERROR);
                return false;
            }
            XmlBuffer tempBuf;
			XmlString tempValue;

            if (entity.value_.length > 0)
            {
                {
                    this.pushContext(entity.value_);
					scope(exit)
						this.popContext();
                    if (!textReplaceCharRef(tempBuf))
                        return false;
					tempValue = sxml!T.data(tempBuf).idup;
                }
				if (inDTD_)
				{
 					auto pcix = tempValue.indexOf('%');
					if (pcix >= 0)
					{
                        sxml!T.assign(tempBuf,tempValue[0..pcix]);
						StringSet!T eset;
						this.pushContext(tempValue[pcix..$]);
						scope(exit)
							this.popContext();
						expandParameterEntities(entity.isInternal_, tempBuf, eset);
						tempValue = sxml!T.data(tempBuf).idup;
					}
				}

                this.pushContext(tempValue);
				scope(exit)
					this.popContext();
                entityContext(entity);

                if (!expandEntityData(tempBuf, stk, reftype))
                {
                    errors_.makeException("ENTITY value has bad or circular Reference",XmlErrorLevel.FATAL);
                    return false;
                }
                if (reftype == RefTagType.SYSTEM_REF)
                    entity.isInternal_ = false;
            }

            entity.value_ = tempValue;
            entity.status_ = EntityData!T.Expanded;
            stk.remove(entity.name_);
            return true;
        }
		else if (entity.status_ == EntityData!T.Expanded)
		{
			return true;
		}
        return false;
    }

	// Set up a new parser, using same IXMLEvents. Use current Xml version
    bool readSystemEntity(EntityData!T entity)
    {
		string uri = to!string(entity.src_.systemId_);
		auto cstr = toStringz(uri);
		// first locate the file, using this parsers system paths.
		if (entity.context_ !is null)
		{
			uri = std.path.buildPath(entity.context_.baseDir_, uri);
		}
		if (!findSystemPath(systemPaths_,uri,uri))
		{
			errors_.pushError(format( "DTD System Entity %s not found",uri), XmlErrorLevel.ERROR);
			entity.status_ = EntityData!T.Failed;
			return false;
		}

		auto ep = prepChildParser();
		auto sf = new XmlFileReader(File(uri,"r"));
		ulong	pos;

		scope(exit)
		{
			ep.explode();
			destroy(ep);
			destroy(sf);
		}
		bool getData(ref const(dchar)[] data)
		{
			return sf.fillData(data,pos);
		}

		ep.initSource(&getData);
        if (ep.matchInput("<?xml"))
        {
            ep.markupDepth++;
            ep.doXmlDeclaration();
        }
        XmlBuffer	edata;
 		ep.frontFilterOn();
		ep.textReplaceCharRef(edata);
		if (sxml!T.length(edata) > 0)
		{
			entity.value_ = sxml!T.data(edata).idup;
			entity.isInternal_ = false;
			entity.baseDir_ = dirName(uri);
			entity.status_ = EntityData!T.Found;
		}
		else {
			entity.status_ = EntityData!T.Expanded;
			entity.value_ = null;
		}
		return true;
    }
    protected bool textReplaceCharRef(ref XmlBuffer app)
    {
        uint radix;
        dchar rchar = 0;
		XmlString ename;

        while (!empty)
        {
            if (lineChar_ >= 0x3FFA)
            {
                radix = 20;
            }
            if (front == '&')
            {
                //startStackID_ = stackID_;
                popFront();
                if (empty)
                    throw makeEmpty();
                if (front == '#')
                {
                    popFront();
                    refToChar(rchar);
                    app ~= rchar;
                }
                else
                {
                    // process the entity name
                    app ~= '&';
                    expectEntityName(ename);
                    app ~= ename;
                    app ~= ';';
                }
            }
            else
            {
                app ~= front;
                popFront();
            }
        }
        return (sxml!T.length(app) > 0);
    }
    void expandParameterEntities(bool isInternal, ref XmlBuffer app, ref StringSet!T stk)
    {
        XmlString evalue;
		//app.clear();// caller has responsibility

        while (!empty)
        {
            switch(front)
            {
				case '%':
					popFront();
					{
						if (!empty && isNameStartFn(front))
						{
							immutable(T)[] entityName;
							if (!getXmlName(entityName) || !matchInput(';'))
								throw badEntityReference();
							auto ed = getParameterEntity(entityName,stk,true);
							if (ed is null)
								throw errors_.makeException(format("Parameter entity %s not found", entityName));
							app ~= ed.value_;
						}
					}
					break;
				default:
					app ~= front;
					popFront();
					break;
            }

        }
        return;
    }
    @property EntityData!T entityContext()
    {
        return entity;
    }

    /// property
    @property void entityContext(EntityData!T val)
    {
        entity = val;
    }
    bool expandEntityData(ref XmlBuffer app, StringSet!T entityNameSet, out int refType)
    {
        uint	  radix;
        bool 	  hitReference = false;

        //ParseInput src = sctx.in_;
		sxml!T.reset(app);
		XmlString ename;

        while (true)
        {
            if (empty)
                break;
            switch(front)
            {
				case '<':
					if (isPIStart())
					{
						doProcessingInstruction();
					}
					else if (matchInput("<![CDATA["))
					{
						sxml!T.append(app,"<![CDATA[");
						bool hitEnd = false;

						while(!empty) // this is to validate the CDATA section ends properly
						{
							if (front == '&')
							{
								popFront();
								if (empty)
									return false;
								if (front == '#')
								{
									dchar cref = expectedCharRef(radix);
									// and output it, still as character reference
									sxml!T.putCharRef(app,cref,radix);
								}
								else
								{
									app ~= '&';
									expectEntityName(ename);
									app ~= ename;
									app ~= ';';
								}
							}
							else if (isCDataEnd())
							{
								sxml!T.append(app,"]]>");
								hitEnd = true;
								break;
							}
							else
							{
								app ~= front;
								popFront();
							}
						}
						if (empty && !hitEnd)
						{
							errors_.pushError("CData section did not terminate",XmlErrorLevel.ERROR);
							return false;
						}
					}
					else
					{
						app ~= front;
						popFront();
					}
					break;
				case '&':
					popFront();
					if (!empty && front=='#')
					{
						dchar uc = expectedCharRef(radix);

						if (uc == '&')
						{
							sxml!T.putCharRef(app,uc,radix);
						}
						else
						{
							app ~= uc;
						}
					}
					else
					{
						expectEntityName(ename);
						auto pc = ename in charEntity;

						if (pc !is null)
						{
							app ~= '&';
							app ~= sxml!T.data(bufTag_);
							app ~= ';';
						}
						else
						{
							int ref2;
							XmlString evalue;
							if (entityNameSet.contains(ename))
								throw errors_.makeException("Circular entity reference");
							if (!lookupReference(ename, entityNameSet, evalue, ref2))
							{
								return false;
							}
							else
							{
								if (ref2 == RefTagType.NOTATION_REF)
								{
									// ignore this reference?
								}
								if (ref2 == RefTagType.SYSTEM_REF)
									refType = RefTagType.SYSTEM_REF; // forced contamination
								app ~= evalue;
								hitReference = true;
							}
						}
					}
					break;
				default:
					app ~= front;
					popFront();
					break;
            } // end switch test
        } // end of data

        if (hitReference)
        {
            this.pushContext(sxml!T.data(app).idup);
			scope(exit)
				this.popContext();
            return expandEntityData(app, entityNameSet, refType);
        }
        return true;
    }
// get ready a parser to read ExternalDTD or System Entity
	private XmlParser!T prepChildParser()
	{
		auto ep = new XmlParser!T();
        ep.isEntity = true;
		ep.validate_ = validate_;
		ep.parentVersion_ = this.docVersion_;
        ep.setXmlVersion(this.docVersion_); // until we know

		// set prepareThrow handler

		ep.eventDg_ = this.eventDg_;
		ep.errors_ = this.errors_;
		ep.results_ = this.results_;
		ep.eventMode_ = true;

        string[]	paths;

        if (inParamEntity())
        {
            paths ~= entity.baseDir_;
        }
        paths ~= systemPaths_;
        ep.systemPaths_ = paths;


		return ep;
	}

    void explode()
	{
		if (dtd_ !is null)
		{
			dtd_.explode();
			dtd_ = null;
		}
		contextStack_.length = 0;
		destroy(this);
	}
    final void expectEntityName(ref XmlString ename)
    {
        if (!getXmlName(ename))
            throw badEntityReference();
        if (empty || front != ';')
            throw badEntityReference();
        popFront(); // pop ;
    }
    EntityData!T getParameterEntity(const(T)[] peName, ref StringSet!T stk, bool isValue = true)
    {
        auto pe = dtd_.getEntity(peName,true);

        if (pe is null)
        {
            return null;
        }

        if (pe.status_ < EntityData!T.Expanded)
        {
			// expand by replacing its internal entities recursively
            if (!stk.put(peName))
            {
                errors_.pushError(format("Recursion for entity: %s ",peName),XmlErrorLevel.ERROR);
                return null;
            }
            if (pe.status_ == EntityData!T.Unknown)
            {
                auto sys_uri = to!string(pe.src_.systemId_);

                if ((sys_uri is null) || (sys_uri.length == 0))
                {
                    errors_.pushError("no system reference for entity",XmlErrorLevel.FATAL);
                    return null;
                }
				if (!readSystemEntity(pe))
					return null;
                //Document doc = new Document();
                /*if (!.getSystemEntity(vp, sys_uri, srcput, baseDir))
                {
                    errors_.pushError("resolve system reference failure", XmlErrorLevel.FATAL);
                    return null;
                }
				pe.isInternal_ = false;
                pe.baseDir_ = baseDir;
                pe.value_ = srcput;
                pe.status_ = EntityData.Found;
				*/

            }
            if (pe.value_.length > 0)
            {
                XmlBuffer	buf1;

                {
					this.pushContext(to!(immutable(T)[])(pe.value_));
					scope(exit)
						this.popContext();
                    if (!doReplaceCharRef(buf1))
                    {
                        errors_.pushError("bad char references",XmlErrorLevel.FATAL);
                        return null;
                    }
                }
                if (isValue)
                {
					this.pushContext(sxml!T.data(buf1).idup);
					scope(exit)
						this.popContext();
					sxml!T.reset(buf1);
                    expandParameterEntities(pe.isInternal_, buf1, stk);
                }
                pe.value(sxml!T.data(buf1).idup);
            }
            pe.status_ = EntityData!T.Expanded;
            stk.remove(peName);
        }
        return pe;
    }
    private final  bool isPIStart()
    {
        if (!empty && (front == '<'))
        {
            markupDepth++;
            popFront();
            if (!empty && (front == '?'))
            {
                popFront();
                return true;
            }
            markupDepth--;
            unpop('<');
        }
        return false;
    }
    bool lookupReference(XmlString entityName, StringSet!T stk, out XmlString value, out int reftype)
    {
        auto entity = dtd_.getEntity(entityName);

        if (entity is null)
        {
            reftype = RefTagType.UNKNOWN_REF;
            return false;
        }
        if (entity.status_ == EntityData!T.Expanded)
        {
            value = entity.value_;
            reftype = entity.reftype_;
            return true;
        }

        if (! deriveEntityContent(entity, stk, reftype))
            return false;

        switch(reftype)
        {
			case RefTagType.SYSTEM_REF:
				entity.isInternal_ = false;
				break;
			case RefTagType.NOTATION_REF:
				if (inGeneralEntity())
					throw errors_.makeException(format("Referenced unparsed data in entity %s", getEntityName()),XmlErrorLevel.ERROR);

				entity.isInternal_ = false;
				entity.status_ = EntityData!T.Expanded;
				entity.reftype_ = cast(RefTagType) reftype;
				break;
			default:
				break;
        }

        if (entity.status_ == EntityData!T.Expanded)
        {
            //Entity xe = new Entity(entity);
            //map.setNamedItem(xe);
            value = entity.value_;
            return true;
        }
        else
        {
            errors_.pushError(text("Value cannot be determined for entity: ",entity.name_),XmlErrorLevel.ERROR);
            return false;
        }
    }

    private bool doReplaceCharRef(ref XmlBuffer app)
    {
        dchar rchar = 0;
		auto beginLength = sxml!T.length(app);

        while (!empty)
        {
			immutable test = front;
            if (test == '&')
            {
                //startStackID_ = stackID_;
                popFront();
                if (empty)
                    throw makeEmpty();
                if (front == '#')
                {
                    popFront();
                    refToChar(rchar);
                    app ~= rchar;
                }
                else
                {
                    // process the entity name
					immutable(T)[] entityName;
                    app ~= '&';
                    if (!getXmlName(entityName) || !matchInput(';'))
						throw badEntityReference();
                    app ~= entityName;
                    app ~= ';';
                }
            }
            else
            {
                app ~= test;
                popFront();
            }
        }
        return (sxml!T.length(app) - beginLength > 0);
    }
    private XmlString getEntityName()
    {
        return entity !is null ? entity.name_ : null;
    }

    void setEventDg(EventDg dg) {
        eventMode_ = (dg !is null);
        eventDg_ = dg;
    }

    private bool fillData(ref const(dchar)[] data)
    {
        return fillSource_.fillData(data,fillPos_);
    }

    public void fillSource(ReadBuffer!dchar src)
    {
        fillSource_ = src;
        initSource(&fillData);
    }

	bool inDTD() const @property
	{
		return inDTD_;
	}

	DocTypeData!T DTD() @property
	{
		return dtd_;
	}

    void setParameter(string name, Variant n)
    {
		switch(name)
		{
			case xmlAttributeNormalize:
				normalizeAttributes_ = n.get!bool;
				break;
			case xmlNamespaces:
				namespaceAware_ = n.get!bool;
				break;
			case xmlCharFilter:
				if (n.get!bool == false)
				{
					filterAlwaysOff();
				}
				break;
			case "edition":
				{
					maxEdition = n.get!uint;
				}
				break;
			default:
				break;
		}
    }
	void addSystemPath(string dir)
	{
		systemPaths_ ~= dir;
	}
    void getLocation(ref SourceRef sref)
    {
        sref.charsOffset = 0;
        sref.lineNumber = lineNumber_;
        sref.colNumber = lineChar_;
    }
    bool namespaces() const
    {
        return namespaceAware_;
    }
    void namespaces(bool doNamespaces)
    {
        namespaceAware_ = doNamespaces;
    }
	@property double xmlVersion() const {
		return filterVersion_;
	}
bool attributeTextReplace(ref XmlBuffer app, uint callct = 0)
    {
		bool result = false; // flag if whitespace replace or entity expansion
	NEXT_CHAR:
        while(!empty)
        {
			immutable test = front;
			switch(test)
			{
				case 0x20:
				case 0x0D:
				case 0x0A:
				case 0x09:
					app ~= cast(char)0x20;
					if (0x20 != test)
						result = true;
					popFront();
					continue NEXT_CHAR;
				case '<':
					throw errors_.makeException("< not allowed in attribute value");
					//break;

				case '&':
					popFront();
					if (empty)
						throw errors_.makeException("single '&' not allowed");
					result = true;
					if (front == '#')
					{
						uint radix;
						dchar cref = expectedCharRef(radix);
						app ~= cref;
						continue NEXT_CHAR;
					}
					XmlString entityName;

					if (!getXmlName(entityName) || !matchInput(';'))
						throw errors_.makeException("single '&' not allowed");

					auto pc = entityName in charEntity;
					if (pc !is null)
					{
						app ~= *pc;
					}
					else
					{
						string evalue;
						auto ed = getEntityData(entityName, true);
						if (ed !is null)
						{
							if (!ed.isInternal_ && this.isStandalone_)
								throw errors_.makeException(format("External entity %s referenced from standalone",entityName));
							this.pushContext(to!(immutable(T)[])(ed.value_));
							scope(exit)
								this.popContext();
							attributeTextReplace(app, callct+1);
						}
						else
						{
							// TODO: put the reference again? exception
							errors_.checkErrorStatus();
						}
					}
					break;
				default:
					app ~= test;
					popFront();
					break;
			}//switch
        }
		return result;
    }
    /// return true if entire name is XML name
    bool isXmlName(const(T)[] dval)
    {
        if(dval.length == 0)
            return false;
        uintptr_t ix = 0;
        dchar test = decode(dval, ix);
        if (!isNameStartFn(test) || isNameStartFifthEdition(test))
            return false;
        while (ix < dval.length)
        {
            test = decode(dval, ix);
            if (!isNameCharFn(test) || isNameCharFifthEdition(test))
                return false;
            if (test == ':' && namespaceAware_)
                return false;
        }
        return true;
    }

	bool isNmToken(const(T)[] dval)
    {
        if(dval.length == 0)
            return false;
        uintptr_t ix = 0;
        while(ix < dval.length)
        {
            if (!isNameCharFn(decode(dval,ix)))
                return false;
        }
        return true;
    }
};

