module xml.xmlLinkDom;

import xml.txml, xml.xmlParser;
import xml.dom.domt;
import xml.textInput, xml.xmlChar, xml.util.read;
import xml.dom.dtdt, xml.xmlError;

import std.file, std.path;

import std.string, std.stdint;
import std.conv, std.algorithm, std.variant, std.array;

debug import std.stdio;
version(GC_STATS)
{
    import xml.util.gcstats;
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

import xml.util.bomstring;







/// check that the URI begins with a scheme name
/// scheme        = alpha *( alpha | digit | "+" | "-" | "." )



class DXmlDomBuild(T) : xmlt!T.IXmlErrorHandler, xmlt!T.IXmlDocHandler
{
    version(GC_STATS)
    {
        mixin GC_statistics;
        static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
    }
	alias xmlt!T.XmlString XmlString;
	alias xmlt!T.xmlNamespaceURI	xmlNamespaceURI;
	alias xmlt!T.xmlnsURI			xmlnsURI;

	alias xmlt!T.XmlBuffer	XmlBuffer;
	alias xmlt!T.XmlEvent XmlEvent;
	alias xmlt!T.IXmlErrorHandler IXmlErrorHandler;


	alias XmlParser!T		Parser;
	alias XMLDOM!T.Node		Node;
	alias XMLDOM!T.ChildNode ChildNode;

	alias XMLDOM!T.AttributeMap		AttributeMap;
	alias XMLDOM!T.AttrNS	AttrNS;
	alias XMLDOM!T.Element	Element;
	alias XMLDOM!T.ElementNS	ElementNS;
	alias XMLDOM!T.Document	 Document;
	alias XMLDOM!(T).NameSpaceSet	NameSpaceSet;
	alias XMLDOM!(T).NamedNodeMap	NamedNodeMap;
	alias XMLDOM!(T).Text	Text;
	alias XMLDOM!(T).DOMConfiguration DOMConfiguration;
	alias XMLDOM!T.DocumentType DocumentType;

	alias XMLDTD!T.IDValidate IDValidate;
	alias XMLDTD!T.DocTypeData DocTypeData;
	alias XMLDTD!T.AttributeDef AttributeDef;
	alias XMLDTD!T.AttributeList AttributeList;
	alias XMLDTD!T.ElementDef  ElementDef;
	alias XMLDTD!T.EntityData EntityData;
	alias XMLDTD!T.isNameSpaceIRI	isNameSpaceIRI;
	alias XMLDTD!T.isNameSpaceURI	isNameSpaceURI;

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
		auto s = new FileReader(srcPath);
		auto sf = new XmlFileReader(s);
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
	DocumentType					dtdNode_; // what the document keeps around
	DocTypeData						dtdData_; // parsed dtd stuff
	IDValidate						idSet_;

	NameSpaceSet		nsSet_;
	bool				namespaceAware_;
	//ParseLevel			;
	ElementLevel		level_;
	ElementLevel[]  	stack_;
	version (TagNesting)
		TagNest!T				rootNest_;

	XmlBuffer				bufChar_;
	XmlBuffer				tagName_;

	string					lastCloseTag_;
	AttributeMap			attrMap_;
	//ImmuteAlloc!(T,true)	stringAlloc_;


	Parser					parser_;
	string[]     			errors_;
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

        parser_ = new Parser();
        parser_.setErrorHandler(this);
        parser_.docInterface = this;
        version(TrackCount)
        {
            tagName_.setid("tagName_");
            bufChar_.setid("bufChar_");
            errors_.setid("Errors");
        }
	}

	void setErrorHandler(IXmlErrorHandler eh)
	{
	}

	void explode()
	{
		parser_.explode();
		destroy(parser_);
		parser_ = null;
	    doc_ = null;
		stack_.length = 0;
		if (nsSet_ !is null)
		{
			nsSet_.explode();
			nsSet_ = null;
		}
		version(TagNesting)
			if (rootNest_)
				rootNest_.explode();
		attrMap_.reset();
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
		errors_ ~= msg;
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
			destroy(errorReport);
		}
		else
			throw errorReport;
	}

	void setEncoding(const(T)[] codeName)
	{
		// this should be done on document print out, or by parser on document.
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
	Exception caughtException(Exception x, XmlErrorLevel level)
	{
		auto s = x.toString();
		pushError(s, level);
		return preThrow(new XmlError(s, level));
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
		errors_ ~= msg;
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
		namespaceAware_ = parser_.namespaces();
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

	string unbindError(XmlString atname)
	{
		return format("Attempt to unbind %s",atname);
	}

	void reviewAttrNS(ElementNS elem)
    {
        // A namespace definition <id> exists if there is a xmlns:<id>="URI" in the tree root.
        // for each attribute, check if the name is a namespace specification

        NamedNodeMap amap = elem.getAttributes();
        if (amap is null)
            return;

        AttrNS rdef;			// attribute which defines a namespace
        AttrNS* pdef;

        // attributes which are not namespace declarations
        AttrNS[]     alist;
        XmlString prefix;
        XmlString nsURI;
        XmlString localName;
        XmlString atname;
		bool      onPrefix;

        auto app = appender(alist);


        bool validate =  parser_.validate();
        int nslistct = 0;

        bool isNameSpaceDef;
        // collect any new namespace definitions
        double xml_version = parser_.xmlVersion();

        // divide the attributes into those that specify namespaces, and those that do not.
        foreach(a ; amap)
        {
            AttrNS nsa = cast(AttrNS) a;
            atname = nsa.getName();

            checkSplitName(atname, prefix, localName);

            if (prefix.length > 0)
            {
                isNameSpaceDef = (cmp("xmlns",prefix) == 0);
				onPrefix = true;
            }
            else
            {
                isNameSpaceDef = (cmp("xmlns",atname) == 0);
				onPrefix = false;
            }

            if (isNameSpaceDef)
            {
                if (nsSet_ is null)
                {
                    nsSet_ = new NameSpaceSet();
                }

                bool bind = true;
                nsURI = nsa.getValue();
                localName = nsa.getLocalName();
                if (nsURI.length == 0) // its an unbinding
                {
                    if (localName.length > 0)
                    {
						if (localName == "xmlns" || localName == "xml")
						{
							if (xml_version == 1)
							{
								if (validate )
									pushError(unbindError(atname),XmlErrorLevel.INVALID);
							}
							else
								throw makeException(unbindError(atname));
						}
                        // default namespace unbinding ok for 1.0
                        bind = false;
                        // is it an error to unbind a non-existing name space?
                        nsSet_.nsdefs_[localName] = nsa; // register as unbound
                    }
                    else
                    {
						if (onPrefix)
							throw makeException(unbindError(atname));
						else
							if (validate && (xml_version == 1))
								pushError(unbindError(atname),XmlErrorLevel.INVALID);
                    }
                }
                else
                {
                    // A bit of validation for the URI / IRI
                    if (xml_version > 1.0)
                    {
                        if (!isNameSpaceIRI(nsURI))
                            throw this.makeException(format("Malformed IRI %s", nsURI),XmlErrorLevel.ERROR);
                    }
                    else if(!isNameSpaceURI(nsURI))
                    {
                        throw this.makeException(format("Malformed URI %s", nsURI),XmlErrorLevel.ERROR);
                    }
                }
                if (bind)
                {
                    // reserved namespaces check
                    if (prefix.length == 0)
                    {
                        if (localName == "xmlns")
                        {
                            if (nsURI == xmlNamespaceURI || nsURI == xmlnsURI)
                                throw this.makeException(format("Cannot set default namespace to %s",nsURI));
							else if (validate && (xml_version == 1))
								pushError("Attempt to bind xmlns",XmlErrorLevel.INVALID);
                        }
                    }
                    else if (prefix == "xml")
                    {
                        if (nsURI != xmlNamespaceURI)
                            throw this.makeException(format("xml namespace URI %s is not the reserved value %s",nsURI, xmlNamespaceURI));

                    }

                    else if (prefix == "xmlns")
                    {
                        if (localName == "xmlns")
                        {
                            throw this.makeException(format("xmlns is reserved, but declared with URI: %s", nsURI));
                        }
                        else if (localName == "xml")
                        {
                            if (nsURI != xmlNamespaceURI)
                                throw this.makeException(format("xml prefix declared incorrectly ", nsURI));
                            else if (validate)
                                this.pushError(format("xml namespace URI %s must only have prefix xml",xmlNamespaceURI),XmlErrorLevel.INVALID);
                            goto DO_BIND;
                        }
                        else if (localName == "xml2")
                        {
                            if (validate)
                                this.pushError("Binding a reserved prefix xml2",XmlErrorLevel.INVALID);
                        }

                        if (nsURI == xmlNamespaceURI)
                        {
                            throw this.makeException(format("xml namespace URI cannot be bound to another prefix: %s", nsURI));
                        }
                        if (nsURI == xmlnsURI)
                        {
                            throw this.makeException(format("xmlns namespace URI cannot be bound to another prefix: %s", nsURI));
                        }
                    }
				DO_BIND:
                    nsSet_.nsdefs_[localName] = nsa; // register as bound to URI value
                }
            }
            else
            {
                app.put(nsa);
            }
        }
        bool needNS;
        alist = app.data();
        // assign namespace URIS

        string noNSMsg(AttrNS ans)
        {
            return format("No namespace for attribute %s",ans.getName());
        }
        foreach(nsa ; alist)
        {
            prefix = nsa.getPrefix();
            needNS = true;
            if (nsSet_ !is null)
            {
                pdef = prefix in nsSet_.nsdefs_;
                if (pdef !is null)
                {
                    rdef = *pdef;

                    if (rdef.getValue() is null)
                        pushError(format("Namespace %s is unbound",prefix),XmlErrorLevel.ERROR);
                    nsa.setURI(rdef.getValue());
                    needNS = false;
                }
            }

            if (needNS)
            {
                if (prefix == "xml")
                {
                    // special allowance
                    if (validate)
                    {
                        pushError("Undeclared namespace 'xml'", XmlErrorLevel.INVALID);
                    }
                }
                else if (prefix.length == 0)
                {
                    if (validate)
                        pushError(noNSMsg(nsa), XmlErrorLevel.INVALID);
                }
                else
					throw this.makeException(noNSMsg(nsa));
            }

        }

        // pairwise check, prove no two attributes with same local name and different prefix have same URI
        if (nsSet_ !is null)
        {
            for(int nix = 0; nix < alist.length; nix++)
            {
                for(int kix = nix+1; kix < alist.length; kix++)
                {
                    AttrNS na = alist[nix];
                    AttrNS ka = alist[kix];

                    if (na.getLocalName() != ka.getLocalName())
                    {
                        continue;
                    }

                    // same local name and prefix is a duplicate name, so the prefixes must be be different.


                    if (na.getNamespaceURI() == ka.getNamespaceURI())
                    {
                        string errMsg = format("Attributes with same local name and default namespace: %s and %s",na.getNodeName(), ka.getName());

                        if (na.getPrefix() is null || ka.getPrefix() is null)
                            pushError(errMsg,XmlErrorLevel.ERROR);
                        else
                            throw this.makeException(errMsg);
                    }
                }
            }
        }
        checkErrorStatus();

        return;
    }
    void reviewElementNS(ElementNS elem)
    {
        // now review element name itself
        XmlString prefix;
        XmlString localName;
        XmlString nsURI;

        checkSplitName(elem.getNodeName(), prefix, localName);

        bool needNS = (prefix.length > 0);

        if (nsSet_ !is null)
        {
            auto pdef = prefix in nsSet_.nsdefs_;
            if (pdef !is null)
            {
                auto rdef = *pdef;
                nsURI = rdef.getValue();
                if (nsURI.length == 0)
                {
                    pushError(format("Namespace %s is unbound",prefix ),XmlErrorLevel.FATAL);
                }
                else
                {
                    elem.setURI(nsURI);
                    needNS = false;
                }
            }

        }
        if (needNS)
        {
            if (prefix == "xmlns")
            {
                throw makeException(format("%s Elements must not have prefix xmlns",elem.getNodeName()));
            }
			// unless this is DOCTYPE defined in a magic way
			if ((this.dtdData_ !is null) && ((this.dtdData_.id_ == elem.getNodeName()) || (level_.def_ !is null)))
			{
				// overrides?
			}
			else
				throw makeException(format("No namespace found for %s", elem.getNodeName()),XmlErrorLevel.FATAL);
        }
        checkErrorStatus();
    }
	void makeTag(ref const XmlEvent s, bool hasContent)
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


		stack_ ~= level_;
		level_.n_ = node;
		level_.e_ = node;
		level_.tag_ = tagName;

		version(TagNesting)
		{
			level_.nest_ = childTag;
		}
		else {
			level_.def_ = (dtdNode_ is null) ? null : dtdData_.elementDefMap.get(tagName,null); // required for validation
		}

		attrMap_.reset();

		// 	collect attributes, check for duplicates, as initial add used push
		if (s.attributes.length > 0)
		{
			// copy parse list
			this.attrMap_ = s.attributes;
			if (!this.attrMap_.sorted)
			{
				this.attrMap_.sort();
				auto dupix = attrMap_.getDuplicateIndex();
				if (dupix >= 0)
				{
					throw makeException(format("Duplicate attribute %s", attrMap_[dupix].value));
				}
			}
			// TODO : review namespaces
		}
		if (dtdData_ !is null)
			validateAttributes();
		// assign finalized set of attributes
		foreach(n,v ; attrMap_)
		{
			node.setAttribute(n,v);
		}

        if (namespaceAware_)
        {
            if (parser_.namespaces())
            {
                ElementNS ens = cast(ElementNS) node;
                if (ens)
                {
					reviewAttrNS(ens);
                    reviewElementNS(ens);
                }
            }
        }

		if (!hasContent)	// no endTag with matching popBack will occur, so pop now.
		{
			auto slen = stack_.length;
			if (slen > 0)
			{
				slen--;
				level_ = stack_[slen];
				stack_.length = slen;
			}
		}
	}

	void init(ref XmlEvent s)
	{
		s = new XmlEvent();
	}
	void soloTag(const XmlEvent  s)
	{
		makeTag(s,false);
	}

	void startTag(const XmlEvent s)
	{
		makeTag(s,true);
	}

	void text(const XmlEvent  s)
	{
		level_.n_.appendChild(new Text(s.data));
	}
	void comment(const XmlEvent  s)
	{
	// comments may be attached at document level
		level_.n_.appendChild(doc_.createComment(s.data));
	}
	void cdata(const XmlEvent  s)
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
	final void declaration(const XmlEvent  s)
	{
		// use the attributes, or
		auto docVersion = s.attributes.get("version","1.0");
		doc_.setXmlVersion(docVersion);
	}

	final void instruction(const XmlEvent  s)
	{
		auto p = s.attributes[0];
		level_.n_.appendChild(doc_.createProcessingInstruction(p.name, p.value));
	}

	final void endTag(const XmlEvent  s)
	{
		if (s.data != level_.tag_)
		{
			throw makeException(format("End tag, expected %s, got %s", level_.tag_, s.data));
		}
		//lastCloseTag_ = level_.tag_;
		//TODO: validations
		auto slen = stack_.length;
		if (slen > 0)
		{
			slen--;
			level_ = stack_[slen];
			stack_.length = slen;
		}

		//debug(VERBOSE) { writeln("end ", currentTag_); }
	}

	void dtdAttributeNormalize(AttributeDef adef, XmlString oldValue, ref XmlString result, AttributeType useType, bool reqExternal)
    {
        XmlBuffer resultBuf;
		bool replace = false;
		{
			parser_.pushContext(oldValue, true, null);
			scope(exit)
				parser_.popContext();
			replace = parser_.attributeTextReplace(resultBuf, 0);
		}
		result = (replace) ? resultBuf.data.idup : oldValue;
        XmlString[] valueset;
        uint vct = 0;
        bool doValidate = parser_.validate();

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
						auto pnote = notate in dtdData_.notationMap;
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
							auto nt = dval in dtdData_.generalEntityMap;
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
        XmlString[]	valueList;

        foreach(adef ; alist.attributes_)
        {
            XmlString[] oldvalues = adef.values;
			valueList.length = 0;
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
            adef.values = valueList;

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
			if (dtdData_ is null)
			{
				parser_.setParameter(xmlAttributeNormalize,Variant(false));
				dtdData_ = parser_.DTD(); // get DocTypeData from parser, but create a DocumentType node
				dtdNode_ = new DocumentType(dtdData_.id_);
				dtdNode_.setSource(dtdData_.src_.publicId_, dtdData_.src_.systemId_);
			}
		}
	}
	void endDoctype(Object p)
	{
		if (dtdNode_ !is null)
		{
			if (doc_.getDoctype() is null)
				doc_.appendChild(dtdNode_);
		}
	}
	void notation(Object n)
	{
		auto ed = cast(EntityData) n;
		if (ed !is null)
		{
			if (dtdNode_ !is null)
			{
				alias XMLDOM!T.Notation Notation;
				auto nob = new Notation(ed.name_);
				nob.setSource(ed.src_.publicId_, ed.src_.systemId_);
				dtdNode_.getNotations().setNamedItem(nob);
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
		auto itList = attrMap_; // get a duplicate list to iterate
		foreach(n,v ; itList)
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
			// alter original list
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
        bool reportExternal = (reportInvalid && (!dtdData_.isInternal_ || !alist.isInternal_));

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
        XmlBuffer	app;
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
                    app ~= ' ';
                    spaceCt = 0;
                }
                app ~= test;
            }
        }

        if (app.data != value)
        {
            value = app.data.idup;
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
	static bool validElementContent(ElementDef edef, Element parent, IXmlErrorHandler events)
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
