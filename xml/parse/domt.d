module xml.parse.domt;

import xml.ixml, xml.parse.dxml;
import alt.buffer;
import xml.dom.domt;
import xml.parse.input, xml.xmlchar, xml.util.read;
import std.stream, std.path;

import std.string, std.stdint, std.conv, std.algorithm, std.variant, std.array;
import xml.util.read;

debug import std.stdio;
version(GC_STATS)
{
    import alt.gcstats;
}

// build up a structure of used tag nesting
// debug = CheckNest
/// Reduce multiple allocations for same element or attribute name. Saves a tiny bit of time.
//version=TagNesting;
//version=MapNames;
version(TagNesting)
{
	import xml.dom.tagnest;
}

import xml.dom.dtdt, xml.xmlerror;
import alt.bomstring;

class DXmlDomBuild(T) : IXmlErrorHandler!T , IXmlDocHandler!T
{
    version(GC_STATS)
    {
        mixin GC_statistics;
        static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
    }
	alias immutable(T)[] XmlString;
	alias XMLDOM!T.Node		Node;
	alias XMLDOM!T.ChildNode ChildNode;

	alias XMLDOM!T.AttributeMap		AttributeMap;
	alias XMLDOM!T.Element	Element;
	alias XMLDOM!T.Document	 Document;
	alias XMLDOM!(T).NameSpaceSet	NameSpaceSet;
	alias XMLDOM!(T).Text	Text;
	alias XMLDOM!(T).DOMConfiguration DOMConfiguration;
	alias XMLDOM!T.DocumentType DocumentType;

	alias XMLDTD!T.IDValidate IDValidate;
	alias XMLDTD!T.DocTypeData DocTypeData;
	alias XMLDTD!T.AttributeDef AttributeDef;
	alias XMLDTD!T.AttributeList AttributeList;
	alias XMLDTD!T.ElementDef  ElementDef;
	alias XMLDTD!T.EntityData EntityData;

	private struct ElementLevel {
		Node		n_;
		Element		e_;
		XmlString	tag_;
		version(TagNesting)
			TagNest!T		nest_;
		else
			ElementDef	def_;
	}

	void parseFile(Document d, string srcPath)
	{
		doc_ = d;
		setFromDocument();
		addSystemPath(normalizedDirName(srcPath));
		auto s = new BufferedFile(srcPath);
		auto sf = new XmlStreamFiller(s);
		parser_.fillSource = sf;
		parser_.parseAll();
	}

	void parseInputDg(Document d, MoreInputDg dg)
	{
		doc_ = d;
		setFromDocument();
		parser_.initSource(dg);
		parser_.parseAll();

	}
	/// parse a potentially different character type.
	void parseNoSlice(S)(Document d, const(S)[] src)
	{
		doc_ = d;
		setFromDocument();
		parser_.fillSource(new SliceFill!S(src));
		parser_.parseAll();
	}
	void parseSlice(Document d, immutable(T)[] src)
	{
		doc_ = d;
		setFromDocument();
		parser_.initSource(src);
		parser_.parseAll();
	}
	// read the data in a block, translate if necessary to T.
	void parseSliceFile(Document d, string srcPath)
	{
		doc_ = d;
		setFromDocument();
		parser_.sliceFile(srcPath);
		parser_.parseAll();
	}

	Document						doc_;
	DocTypeData						dtd_;
	IDValidate						idSet_;

	NameSpaceSet		nsSet_;
	bool				namespaceAware_;
	//ParseLevel			;
	ElementLevel		level_;
	Buffer!ElementLevel	stack_;
	version (TagNesting)
		TagNest!T				rootNest_;

	Buffer!T				bufChar_;
	Buffer!T				tagName_;

	string					lastCloseTag_;
	AttributeMap			attrMap_;
	//ImmuteAlloc!(T,true)	stringAlloc_;


	DXmlParser!T			parser_;
	Buffer!string			errors_;
	XmlErrorLevel			maxError_;

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
	}

	this()
	{
        version(GC_STATS)
        {
            version(GC_STATS)
                gcStatsSum.inc();
        }

        parser_ = new DXmlParser!T();
        parser_.errorInterface = this;
        parser_.docInterface = this;
        version(TrackCount)
        {
            tagName_.setid("tagName_");
            bufChar_.setid("bufChar_");
            errors_.setid("Errors");
        }
	}


	void explode()
	{
		parser_.explode();
		parser_ = null;
	    doc_ = null;
		stack_.forget();
		version(TagNesting)
			if (rootNest_)
				rootNest_.explode();
		attrMap_.explode();
	}

	void validate(bool doCheck=true)
	{
		parser_.validate = doCheck;
	}

	void addSystemPath(string dir)
	{
		parser_.addSystemPath(dir);
	}

	private void pushInvalid(string msg)
	{
		errors_.put(msg);
		if (maxError_ < XmlErrorLevel.INVALID)
			maxError_ = XmlErrorLevel.INVALID;
	}

	void checkErrorStatus()
	{
		auto errorStatus = maxError_;
		if (maxError_ == XmlErrorLevel.OK)
			return;

		auto errorReport = makeException("Errors recorded",maxError_);
		if (maxError_ < XmlErrorLevel.ERROR)
		{
			maxError_ = XmlErrorLevel.OK;
			errors_.length = 0;
		}
		else
			throw errorReport;
	}

	/// just return the entity name, not decoded
	void entityName(const(T)[] s,bool inAttribute)
	{

	}

	void setEncoding(const(T)[] codeName)
	{
	}


	XmlError preThrow(XmlError ex)
	{
		auto conf = doc_.getDomConfig();
		Variant v = conf.getParameter("error-handler");
		DOMErrorHandler* peh = v.peek!(DOMErrorHandler);
		if (peh !is null)
		{
			auto eh = *peh;
			SourceRef spos;
			parser_.getLocation(spos);
			return preThrowHandler(ex, eh, spos);
		}
		return ex;
	}
	Exception caughtException(Exception x)
	{
		auto s = x.toString();
		pushError(s, XmlErrorLevel.FATAL);
		return preThrow(new XmlError(s, XmlErrorLevel.FATAL));
	}

	Exception makeException(string s, XmlErrorLevel level = XmlErrorLevel.FATAL)
	{
		pushError(s, level);
		auto report = new XmlError(s, level);
		report.errorList = errors_.dup;
		return preThrow(report);
	}

	Exception makeException(XmlErrorCode code)
	{
		return makeException(getXmlErrorMsg(code), XmlErrorLevel.FATAL);
	}

	XmlErrorLevel pushError(string msg, XmlErrorLevel level)
	{
		errors_.put(msg);
		if (maxError_ < level)
			maxError_ = level;
		return maxError_;
	}
    protected void checkSplitName(XmlString aName, ref XmlString nsPrefix, ref XmlString nsLocal)
    {
        uintptr_t sepct = XMLDOM!T.splitNameSpace(aName, nsPrefix, nsLocal);

        if (sepct > 0)
        {
            if (sepct > 1)
                throw makeException(format("Multiple ':' in name %s ",aName));
            if (nsLocal.length == 0)
                 throw makeException(format("':' at end of name %s",aName));
            if (nsPrefix.length == 0)
                 throw makeException(format("':' at beginning of name %s ",aName));
        }
    }

	void setFromDocument()
	{
		level_.n_ = doc_;
		DOMConfiguration conf = doc_.getDomConfig();
		auto list = conf.getParameterNames();
		foreach(s ; list.items())
		{
			auto v = conf.getParameter(s);
			parser_.setParameter(s,v);
		}
	}

    void setParameter(string name, Variant n)
    {
		switch(name)
		{
			/*
			case xmlAttributeNormalize:
				parser_.normalizeAttributes_ = n.get!bool;
				break;

			case "fragment":
				fragmentReturn(n.get!bool);
				break;
			*/
			case xmlNamespaces:
				namespaceAware_ = n.get!bool;
				break;
			/*
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
				break;*/
			default:
				break;
		}
    }


	void makeTag(ref XmlEvent!T s, bool hasContent)
	{
		XmlString		tagName = s.data;

		version(TagNesting)
		{
			TagNest!T		childTag;
			TagNest!T		parentTag = level_.nest_;

			void makeTagNest()
			{
				auto def = (dtd_ is null) ? null : dtd_.elementDefMap.get(tagName,null);
				childTag =  new TagNest!T(tagName, cast(void*)def);
				if (parentTag !is null)
					parentTag.addChild(childTag);
			}

			if (parentTag !is null)
			{
				childTag = parentTag.findChild(tagName);
				if (childTag !is null)
				{
					tagName = childTag.tag_;
					debug(CheckNest) gAllocSaved++;
				}
				else {
					// This is the first time for this tag
					makeTagNest();
				}
			}
			else {
				makeTagNest();
				rootNest_ = childTag;
			}
		}

		auto node = doc_.createElement(tagName);
		level_.n_.appendChild(node);


		stack_.put(level_);
		level_.n_ = node;
		level_.e_ = node;
		level_.tag_ = tagName;

		version(TagNesting)
		{
			level_.nest_ = childTag;
		}
		else {
			level_.def_ = (dtd_ is null) ? null : dtd_.elementDefMap.get(tagName,null); // required for validation
		}

		attrMap_.clear();

		// 	collect attributes
		if (s.attributes.length > 0)
		{
			attrMap_ = s.attributes;


			if (attrMap_.length > 1)
			{
				attrMap_.sort();
				auto dupix = attrMap_.getDuplicateIndex();
				if (dupix >= 0)
				{
					throw makeException(format("Duplicate attribute %s", attrMap_.atIndex(dupix).value));
				}
			}
			// TODO : review namespaces

		}
		if (dtd_ !is null)
			validateAttributes();
		foreach(n,v ; attrMap_)
		{
			node.setAttribute(n,v);
		}
		if (!hasContent)	// no endTag with matching popBack will occur, so pop now.
		{
			level_ = stack_.movePopBack();
		}
	}

	void init(ref XmlEvent!T s)
	{
		s = new XmlEvent!T();
	}
	void soloTag(XmlEvent!T s)
	{
		makeTag(s,false);
	}

	void startTag(XmlEvent!T s)
	{
		makeTag(s,true);
	}

	void text(XmlEvent!T s)
	{
		level_.n_.appendChild(new Text(s.data));
	}
	void comment(XmlEvent!T s)
	{
	// comments may be attached at document level
		level_.n_.appendChild(doc_.createComment(s.data));
	}
	void cdata(XmlEvent!T s)
	{
		version(TagNesting)
			auto edef = cast(ElementDef) level_.nest_.info_;
		else
			auto edef = level_.def_;

		auto n = (edef !is null) && (edef.hasPCData)
			? doc_.createTextNode(s.data)
			: doc_.createCDATASection(s.data);
		level_.n_.appendChild(n);
	}
	final void declaration(XmlEvent!T s)
	{

	}

	final void instruction(XmlEvent!T s)
	{
		auto p = s.attr.atIndex(0);
		level_.n_.appendChild(doc_.createProcessingInstruction(p.id, p.value));
	}

	final void endTag(XmlEvent!T s)
	{
		if (s.data != level_.tag_)
		{
			throw makeException(format("End tag, expected %s, got %s", level_.tag_, s.data));
		}
		//lastCloseTag_ = level_.tag_;
		//TODO: validations
		if (stack_.length > 0)
			level_ = stack_.movePopBack();

		//debug(VERBOSE) { writeln("end ", currentTag_); }
	}

	void dtdAttributeNormalize(AttributeDef adef, XmlString oldValue, ref XmlString result, AttributeType useType, bool reqExternal)
    {
        Buffer!T resultBuf;
		{
			parser_.pushContext(oldValue, true, null);
			scope(exit)
				parser_.popContext();
			parser_.attributeTextReplace(resultBuf, 0);
		}

        XmlString[] valueset;
        uint vct = 0;
        bool replace = false;
        bool doValidate = parser_.validate();
		result = to!XmlString(resultBuf.peek);

        auto oldLength = result.length; // check for trimming
        switch(useType)
        {
			case AttributeType.att_id:
				result = strip(result);
				if (doValidate)
				{
					if (!parser_.isXmlName(result))
						pushError(format("ID value %s is not a proper XML name", result),XmlErrorLevel.INVALID);
					XmlString elemId = adef.attList.id;
					if (idSet_ is null)
						throw makeException("no validation of ID configured");
					bool isUnique = idSet_.mapElementID(elemId, result);
					if (!isUnique)
					{
						XmlString existingElementName = idSet_.idElements[result];
						pushError(format("non-unique ID value %s already in element %s ", result,existingElementName),XmlErrorLevel.INVALID);
					}
				}
				break;
			case AttributeType.att_notation:
				// make sure the notation exists, but only if an attribute list is referenced
				if (doValidate)
				{
					foreach(notate ; adef.values)
					{
						auto pnote = notate in dtd_.notationMap;
						if (pnote is null)
							pushInvalid(format("ATTLIST refers to undeclared notation %s",notate));
					}
				}
				break;
			case AttributeType.att_enumeration:
				{
					// value must be one of the listed values
					result = strip(result);
					if (doValidate)
					{
						bool isListed = false;
						foreach(v ; adef.values)
						{
							if (result == v)
							{
								isListed = true;
								break;
							}
						}
						if ( !isListed)
							pushInvalid(format("value %s  not listed in ATTRLIST",result));
					}
				}
				break;

			case AttributeType.att_entity:
			case AttributeType.att_entities:
				if (normalizeSpace(result) && !adef.isInternal)
					reqExternal = true;
				result = stripLeft(result);
				if (doValidate)
				{
					valueset = split(result);
					vct = cast(uint) valueset.length;

					if ((useType == AttributeType.att_entity) && (vct != 1))
					{
						pushInvalid(format("Value not a valid entity name: %s",result));
						break;
					}

					foreach(dval ; valueset)
					{
						if (!parser_.isXmlName(dval))
						{
							pushInvalid(format("Value %s not a valid entity name: ",dval));
						}
						else
						{
							auto nt = dval in dtd_.generalEntityMap;
							if ( nt is null)
							{
								pushInvalid(format("attribute %s : value is not an ENTITY: %s ",adef.id,dval));
							}
							else
							{
								// should be an unparsed entity, ie have an ndata_ref
								auto ent = *nt;
								if (nt.ndataref_.length == 0)
								{
									pushInvalid(format("attribute %s : value is not an NDATA ENTITY: %s ",adef.id,dval));
								}
							}
						}
					}
					if (vct == 0)
						pushInvalid("Should be at least one value in idref | idrefs");
				}
				break;

			case AttributeType.att_nmtoken:
			case AttributeType.att_nmtokens:

				if (normalizeSpace(result) && !adef.isInternal)
					reqExternal = true;
				result = stripLeft(result);
				if (!doValidate)
					break;

				valueset = split(result);
				vct = cast(uint) valueset.length;
				replace = false;

				if (useType == AttributeType.att_nmtoken)
				{
					if (vct > 1)
						pushInvalid(format("Value not a single NMTOKEN name: %s",result));
				}
				foreach(dval ; valueset)
				{
					if (!parser_.isNmToken(dval))
					{
						pushInvalid(format("Value not a valid NMTOKEN: ",dval));
					}
				}
				if (vct == 0)
					pushInvalid("Should be at least one value in idref | idrefs");
				break;
			case AttributeType.att_idref:
			case AttributeType.att_idrefs:
				result = stripLeft(result);
				if (normalizeSpace(result) && !adef.isInternal)
					reqExternal = true;
				if (doValidate)
				{
					valueset = split(result);
					vct = cast(uint) valueset.length;

					if ((useType == AttributeType.att_idref)&&(vct != 1))
					{
						pushInvalid(format("Value not a valid IDREF name: %s",result));
					}
					foreach(dval ; valueset)
					{
						if (!parser_.isXmlName(dval))
						{
							pushInvalid(format("Value not a valid reference: %s",dval));
						}
						else if (idSet_ !is null)
						{
							idSet_.checkIDRef(dval);
						}
					}
					if (vct == 0)
						pushInvalid("Should be at least one value in idref | idrefs");
				}
				break;
			default:
				break;
        }
        if ((result.length != oldLength) && !adef.isInternal)
            reqExternal = true;
    }
    private bool normaliseAttributeList(AttributeList alist)
    {
        bool doValidate = parser_.validate();
        bool reportExternal = doValidate && parser_.isStandalone();
        PackedArray!T	valueList;

        foreach(adef ; alist.attributes_)
        {
            XmlString[] oldvalues = adef.values;
            if ((adef.dataform == AttributeType.att_idref)
				||(adef.dataform == AttributeType.att_idrefs)
				||(adef.dataform == AttributeType.att_id)
				)
            {
                if (doValidate && (idSet_ is null))
                    idSet_ = new IDValidate();
            }
            foreach(i, sv ; oldvalues)
            {
                bool reqExternal = false;
                XmlString result;
                dtdAttributeNormalize(adef, sv, result, adef.dataform, reqExternal);
                if (reportExternal && reqExternal)
                    pushInvalid(format("attribute requires external document for normalisation: %s",adef.id));
                valueList ~= result;
            }
            adef.values = valueList.idup();
        }
        if (maxError_ > 0)
        {
            pushInvalid(format("Errors during ATTLIST normalisation for %s",alist.id));
            checkErrorStatus();
        }
        return true;
    }
	void startDoctype(Object p)
	{
		if (p is parser_)
		{
			parser_.setParameter(xmlAttributeNormalize,Variant(false));
			dtd_ = parser_.DTD();
			auto dtype = doc_.getDoctype();
			if (dtype is null)
			{
				dtype = new DocumentType(dtd_.id_);
				dtype.setSource(dtd_.src_.publicId_,dtd_.src_.systemId_);
				doc_.appendChild(dtype);
			}
			else {
				/// TODO : Tell parser not to bother so hard?
			}
		}
	}
	void endDoctype(Object p)
	{
		/// nothing to do?
	}
	void notation(Object n)
	{
		auto ed = cast(EntityData) n;
		if (ed !is null)
		{
			auto dtype = doc_.getDoctype();
			if (dtype !is null)
			{
				alias XMLDOM!T.Notation Notation;
				auto nob = new Notation(ed.name_);
				nob.setSource(ed.src_.publicId_, ed.src_.systemId_);
				dtype.getNotations().setNamedItem(nob);
			}
		}
	}

    /// Validate the Attributes.
    private void validateAttributes()
    {
        bool doValidate = parser_.validate();

        // see that each attribute was declared
        AttributeDef	atdef;
        AttributeList	atlist;
        AttributeType	attype;

        XmlString aValue;
		version(TagNesting)
		{
			auto edef = (level_.nest_.info_ !is null) ? cast(ElementDef) level_.nest_.info_ : null;
		}
		else
			auto edef = level_.def_;

        if (edef !is null)
        {

            atlist = edef.attrList;

            if (atlist !is null)
            {
                if (!atlist.isNormalised_)
                    normaliseAttributeList(atlist);
            }
            else if (doValidate && (attrMap_.length > 0))
            {
                pushInvalid(format("No attributes defined for element %s",level_.tag_));
                return;
            }
        }

		foreach(n,v ; attrMap_)
		{
			atdef = null;

			if (atlist !is null)
			{
				auto padef = n in atlist.attributes_;
				/// TODO : if not validating, treat not declared as CDATA
				if (padef is null)
				{
					if (doValidate)
						pushInvalid(format("Attribute not declared: %s",n));
				}
				else
				{
					atdef = *padef;
				}
			}

			attype = (atdef is null) ? AttributeType.att_cdata : atdef.dataform;
			bool reqExternal = false;
			dtdAttributeNormalize(atdef, v, aValue, attype, reqExternal);
			if (v != aValue)
				attrMap_[n] = aValue;
		}

        if (atlist !is null)
            addDefaultAttributes(atlist);
        if (doValidate)
        {
            if (maxError_ != 0)
                checkErrorStatus();
        }
    }
	/**
	Insert missing attributes which have a default value.
    */
    private bool addDefaultAttributes(AttributeList alist)
    {
        XmlString value;
        XmlString* pvalue;

        bool doValidate = parser_.validate();
        bool reportInvalid = doValidate && parser_.isStandalone();
        bool reportExternal = (reportInvalid && (!dtd_.isInternal_ || !alist.isInternal_));

        XmlString getDefaultValue(AttributeDef adef)
        {
            if (reportExternal && (!adef.isInternal))
                pushInvalid(format("standalone yes but default specfied in external: %s ", adef.id));
            return adef.values[adef.defaultIndex];
        }

		//hash.arraymap.HashTable!(string,string)		attrMap;
		// As long as no removals, keys and values will have no holes.
		//attrMap.setKeyValues(ret.names, ret.values);
        foreach(adef ; alist.attributes_)
        {
            value = attrMap_.get(adef.id,null);
            switch (adef.require)
            {
				case AttributeDefault.df_fixed:
					{
						XmlString fixed = adef.values[adef.defaultIndex];
						if (value is null)
						{
							if (reportInvalid && !alist.isInternal_)
								pushInvalid(format("standalone and value fixed in external dtd: %s",fixed));
							attrMap_[adef.id] = fixed;
						}
						else
						{
							if ((value != fixed) && doValidate)
								pushInvalid(format("Attribute %s fixed value %s ", adef.id, value));
						}
					}
					break;
				case AttributeDefault.df_implied:
					break;
				case AttributeDefault.df_required:
					if (value is null)
					{
						if (adef.defaultIndex >= 0)
						{
							attrMap_[adef.id] = getDefaultValue(adef);
						}
						else
						{
							pushInvalid(format("Element %s requires attribute: %s ", level_.tag_, adef.id));
						}
					}
					break;
				default:
					if ((adef.defaultIndex >= 0) && (value is null))
					{
						attrMap_[adef.id] = getDefaultValue(adef);
					}
					break;
            }
        }
        return true;
    }
    private bool normalizeSpace(ref XmlString value)
    {
        Buffer!T	app;
        app.reserve(value.length);
        int spaceCt = 0;
        // only care about space characters
        for (size_t ix = 0; ix < value.length; ix++)
        {
            T test = value[ix];
            if (isSpace(test))
            {
                spaceCt++;
            }
            else
            {
                if (spaceCt)
                {
                    app.put(' ');
                    spaceCt = 0;
                }
                app.put(test);
            }
        }

        auto result = app.peek;
        if (result != value)
        {
            value = app.idup;
            return true;
        }
        return false;
    }

	alias XMLDTD!(T).ChildElemList ChildElemList;
	alias XMLDTD!(T).ChildId ChildId;
	alias XMLDTD!(T).FelEntry FelEntry;
	alias XMLDTD!(T).FelType FelType;
	alias XMLDTD!(T).toDTDString toDTDString;
	private struct clistinfo
	{
		ChildElemList  clist;
		bool	   	   match;
		intptr_t	   pIndex;
		intptr_t	   eIndex;

		void init(ChildElemList c, bool m, intptr_t fix, intptr_t eix)
		{
			clist = c;
			match = m;
			pIndex = fix;
			eIndex = eix;
		}
	}

	/// Given the ElementDef, check Element has conforming children
	static bool validElementContent(ElementDef edef, Element parent, IXmlErrorHandler!T events)
	{
		// collect the children in temporary
		Node nd1 = parent.getFirstChild();
		Node[] seq  = (nd1 !is null) ? ChildNode.getNodeList(cast(ChildNode)nd1) : [];

		if (edef.flatList.length == 0)
		{
			edef.makeFlatList();
			if (edef.flatList.length == 0)
			{
				return true; // only concerned about missing elements
			}
		}
		// go through the flatlist, and ensure any mandatory elements
		// are present
		intptr_t elemIX = 0;
		intptr_t startElemIX = 0;

		auto limit = seq.length;
		ChildId ce;
		intptr_t itemIX = 0;
		bool needAnotherChoice = false;

		clistinfo[]  estack;
		ChildElemList clist;
		Element child;



		bool hasAnotherChoice()
		{
			// muast be do or die call
			// tried sequence is invalid, so is it part of another choice in the stack?
			// if so we need to take the elements consumed back for the alternate
			// and pop stack properly
			intptr_t failtop = estack.length-1;
			intptr_t top = failtop - 1;
			intptr_t endIX = itemIX - 1;  // start on the current FelEntry
			FelEntry[]	 list = edef.flatList;

			while (top >= 0)
			{
				// failtop has a parent, so go to end of failtop, and see if
				// there is another choice
				while (endIX < list.length)
				{
					if (list[endIX].fel == FelType.fel_listend)
					{
						break;
					}
					endIX++;
				}
				// could assert here that the clist of listend is failtop

				if (endIX >= list.length)
					return false;

				if (estack[top].clist.select == ChildSelect.sl_choice)
				{
					// move along to next choice by moving past listend
					elemIX = estack[failtop].eIndex;
					itemIX = endIX + 1;
					estack.length = top+1;
					return true;
				}
				else
				{
					endIX++; // move into next territory
				}
				failtop -= 1;
				top -= 1;
			}
			return false;
		}


		Element nextElement()
		{
			while(elemIX < limit)
			{
				Element result = cast(Element)seq[elemIX];
				if (result !is null)
					return result;
				elemIX++;
			}
			return null;
		}

		bool isNextElementMatch(XmlString id)
		{
			child = nextElement();
			return (child !is null) && (child.getTagName()==id);
		}
		void consumeId(XmlString id)
		{
			Element ch = nextElement();
			while (ch !is null)
			{
				if (ch.getTagName() == id)
					elemIX++;
				else
					break;
				ch = nextElement();
			}
		}
		void pushError(string s)
		{
			events.pushError(s,XmlErrorLevel.FATAL);
		}
		bool badSequence()
		{
			pushError(format("Missing element choice of %s",toDTDString(edef.flatList,itemIX)));
			return false;
		}
		clistinfo* stacktop;

		while (itemIX < edef.flatList.length)
		{
			FelEntry s = edef.flatList[itemIX++];

			switch(s.fel)
			{
				case FelType.fel_listbegin:
					clist = cast(ChildElemList) s.item;
					// stack top will point to first item after list begin
					estack.length = estack.length + 1;
					estack[$-1].init(clist,false, itemIX, elemIX);
					break;
				case FelType.fel_listend:
					bool noPop = false;
					if (estack.length > 0)
					{
						stacktop = &estack[$-1];
						if (clist.select == ChildSelect.sl_choice)
						{
							if (!stacktop.match && ((clist.occurs & ChildOccurs.oc_one) > 0))
							{
								if (!hasAnotherChoice())
								{
									if ((clist.occurs & ChildOccurs.oc_allow_zero)==0)
										return badSequence();
									else
									{
										stacktop.match = true;
									}
								}
								break;
							}

						}
						else
						{
							// if we got here, presume that a sequence matched
							stacktop.match = true;
						}
						if ((nextElement() !is null) && ((clist.occurs & ChildOccurs.oc_allow_many) > 0) && (elemIX > startElemIX))
						{
							// made progress, so run again to see if it matches again

							itemIX = stacktop.pIndex;
							startElemIX = elemIX;
							stacktop.match = false;
							noPop = true;
						}

						if (!noPop)
						{
							// presumably this list was satisfied here?
							// if it was a member of parent list choice, need to inform that
							auto  slen = estack.length-1;
							bool wasMatch = estack[slen].match;
							estack.length = slen;

							if (slen > 0)
							{
								slen--;
								clist = estack[slen].clist;
								if (clist.select == ChildSelect.sl_choice)
									estack[slen].match = wasMatch;
							}

						}
					}
					break;
				case FelType.fel_element:
					ce = cast(ChildId) s.item;
					stacktop = &estack[$-1];
					if (clist.select == ChildSelect.sl_choice)
					{

						if (!stacktop.match)
						{
							if (isNextElementMatch(ce.id))
							{
								stacktop.match = true;
								elemIX++;
							}
						}
					}
					else
					{
						if ((clist.occurs & ChildOccurs.oc_one) > 0
							&&(ce.occurs & ChildOccurs.oc_one) > 0)
						{
							// sequence must match
							if (!isNextElementMatch(ce.id))
							{
								if ((ce.occurs & ChildOccurs.oc_allow_zero)==0)
								{
									if (!hasAnotherChoice())
									{
										return badSequence();
									}
								}
								break;
							}
							elemIX++;
							if ((ce.occurs & ChildOccurs.oc_allow_many) > 0)
							{
								// more elements might match this
								consumeId(ce.id);
							}
						}
						else if ((ce.occurs & ChildOccurs.oc_one) > 0 && !stacktop.match)
						{
							// optional list sequence, but if occurred, then move up item list
							// sequence may match, and if it does, must complete the sequence?

							if (isNextElementMatch(ce.id))
							{
								elemIX++;
								stacktop.match = true;
								if ((ce.occurs & ChildOccurs.oc_allow_many) > 0)
								{
									consumeId(ce.id);
								}
							}
						}
						else if ((ce.occurs & ChildOccurs.oc_one) > 0)
						{
							// matched one already, must match any others

							if (isNextElementMatch(ce.id) || (child is null))
							{
								pushError(format("missing seq from %s ",toDTDString(edef.flatList,itemIX)));
								return false;
							}
							elemIX++;
						}
						else if ((ce.occurs & ChildOccurs.oc_allow_zero) > 0)
						{
							// allowed zeroOne or zeroMany
							// if it is there, must account for it.
							if (isNextElementMatch(ce.id))
							{
								elemIX++;
								if ((ce.occurs & ChildOccurs.oc_allow_many) > 0)
								{
									consumeId(ce.id);
								}
							}
						}
					}
					break;
				default:
					break;
			}
		}
		// consumed the list, if elements still in Items, they are invalid?
		Element remains = nextElement();
		while (remains !is null)
		{
			elemIX++;
			pushError(format("Element %s is invalid child",remains.getTagName()));
			//remains = nextElement();
			return false;

		}
		return true;
	}
}
void parseXml(T,S)(XMLDOM!T.Document doc, immutable(S)[] sxml, bool validate = true)
{
	auto builder = new DXmlDomBuild!(T)();
	scope(exit)
        builder.explode();
    builder.validate(validate);
	builder.parseNoSlice!S(doc, sxml);
}
void parseXmlSlice(T)(XMLDOM!T.Document doc, immutable(T)[] sxml, bool validate = true)
{
	auto builder = new DXmlDomBuild!(T)();
	scope(exit)
        builder.explode();
    builder.validate(validate);
	builder.parseSlice(doc, sxml);
}

/// Append to DOM document from contents of xml file. Strings sliced from document if/where possible.
void parseXmlSliceFile(T)(XMLDOM!T.Document doc, string srcpath, bool validate = true )
{
	auto builder = new DXmlDomBuild!T();
	scope(exit)
        builder.explode();
	builder.validate(validate);
	builder.parseSliceFile(doc, srcpath);
}
/// Append to DOM document from contents of xml file. Text and element names created on the fly.

void parseXmlFile(T)(XMLDOM!T.Document doc, string srcpath, bool validate = true )
{
	auto builder = new DXmlDomBuild!T();
	scope(exit)
        builder.explode();
	builder.validate(validate);
	builder.parseFile(doc, srcpath);
}
