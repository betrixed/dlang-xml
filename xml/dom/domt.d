/**
	A DOM very similar to Java DOM.
	with navigation between linked parent, child and sibling nodes.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

For larger Documents, with 1000's of element nodes, it is advisable to call the Document method
explode, because the GC may find the inter-linked pointer relationships indigestable. Demolishers,
should be aware the GC will terminate with an exception, if any other references to deleted objects are extant after calling explode.
Element subtrees of Document need to be removed from the Document tree before explode is called, if they are to be kept around.
Only linked Nodes are deleted. String content, is considered untouchable and is left entirely alone for the GC.

*/

module xml.dom.domt;

import std.stdint;
import std.conv;
import std.array;
import xml.util.buffer;

import std.string;
import core.memory;
import core.stdc.string;
import xml.txml;
import xml.xmlOutput;
import xml.attribute;

import std.exception;
import xml.error;



version(GC_STATS) {
	import xml.util.gcstats;
}
/// This modules exception class
class DOMFail : Exception
{
    this(string msg)
    {
        super(msg);
    }
}

void DOMClassException(string msg, string name) //throw(DOMFail*)
{
    throw new DOMFail(text(msg,name));
}


void notImplemented(string msg)
{
    throw new DOMFail(text("Not implemented: ",msg));
}

import std.algorithm;
/// Java dom class name for a string[] wrapper
class StringList(T)
{
	alias immutable(T)[] StringType;
protected:
    StringType[] items_;
	bool		 sorted_;
public:

    this()
    {
    }


    /// Its quite simple
    StringType[] items()
    {
        return items_;
    }

	void doSort()
	{
		sorted_ = true;
		sort(items_);
	}
    /// Its quite simple
    this( StringType[] list)
    {
        items_ = list;
    }
    /// Simple search
    bool contains(StringType s)
    {

        for(uint i = 0; i < items_.length; i++)
            if (cmp(s,items_[i]) == 0)
                return true;
        return false;
    }
    /// property
    @property final uintptr_t getLength()
    {
        return items_.length;
    }

    /// checked access
    StringType item(uintptr_t ix)
    {
        if	(ix >= items_.length)
            return null;
        return items_[ix];
    }

};

template XMLDOM(T)
{
	alias immutable(T)[]        XmlString;

	static if (is(T==char))
		alias std.conv.text	 concats;
	else static if (is(T==wchar))
		alias std.conv.wtext concats;
	else
		alias std.conv.dtext concats;

	alias void delegate(const(T)[] s)	StringPutDg;


alias scope int delegate(Node n) NodeVisitFn;
alias int function(Node n1, Node n2) NodeCompareFn;

/// Base class of all DOM Nodes, following much of DOM interface.
/// This class has one string field to hold whatever the child wants.
/// This class is abstract. Most methods do nothing.
abstract class Node
{
	/// return a node as a string value


	version(GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
    package
    {
        XmlString  id_;
    }
public:
    /// construct
	version(GC_STATS)
	{
		~this()
		{
			gcStatsSum.dec();
		}
	}
	this()
	{
		version(GC_STATS)
			gcStatsSum.inc();
	}

    /// construct
    this(XmlString id)
    {
        id_ = id;
		version(GC_STATS)
			gcStatsSum.inc();
    }
    /// hashable on id_
    override const hash_t toHash()
    {
        return typeid(id_).getHash(&id_);
    }

    /// DOM method returns null, to support non named descendents
    XmlString getNodeName()
    {
        return null;
    }
    /// DOM method returns id_ to support text node descendents;
    XmlString getNodeValue()
    {
        return id_;
    }

    /// DOM method
    void setNodeValue(XmlString val)
    {
        id_ = val;
    }
    /// DOM method
    abstract const NodeType getNodeType();
    /// DOM method
    NodeList getChildNodes()
    {
        notImplemented("cloneNode");
        return null;
    }
    /// DOM method returns null,
    Node getFirstChild()
    {
        return null;
    }
    /// DOM method returns null,
    Node getLastChild()
    {
        return null;
    }
    /// DOM method returns null,
    Node getPreviousSibling()
    {
        return null;
    }
    /// DOM method returns null,
	Node getNextSibling()
    {
        return null;
    }
    /// DOM method returns null,
    NamedNodeMap getAttributes()
    {
        return null;
    }
    /// DOM method returns null,
    Document getOwnerDocument()
    {
        return null;
    }
    /// DOM method returns null,
    Node insertBefore(Node newChild, Node refChild)
    {
        notImplemented("insertBefore");
        return null;
    }
    /// DOM method returns null,
    Node replaceChild(Node newChild, Node oldChild)
    {
        notImplemented("replaceChild");
        return null;
    }
    /// DOM method returns null,
    Node removeChild(Node oldChild)
    {
        notImplemented("removeChild");
        return null;
    }

    /// DOM method returns null,
    Node appendChild(Node newChild)
    {
        notImplemented("appendChild");
        return null;
    }

    /// DOM method returns false,
    bool hasChildNodes()
    {
        return false;
    }

    /// DOM method returns null,
    Node cloneNode(bool deep)
    {
        notImplemented("cloneNode");
        return null;
    }

	/**
	Pre-emptive strike to devastate object, and possibly delete at same NStile.
	Destructor, must call with del false, and ideally explode can tell,
	if its job is already done.
	*/

	void explode()
	{
		this.destroy();
	}


    /// Not supported
    void normalize() {}

    /// Not supported, yet, returns false
    bool isSupported(XmlString feature, XmlString versionStr)
    {
        return false;
    }

    /// DOM method returns null,
    XmlString getNamespaceURI()
    {
        return null;
    }

    /// DOM method returns null,
    XmlString getPrefix()
    {
        return null;
    }

    /// DOM method
    void setPrefix(string prefix)
    {
        notImplemented("prefix");
    }

    /// DOM method returns null,
    XmlString getLocalName()
    {
        return null;
    }

    /// DOM method returns false,
    bool hasAttributes()
    {
        return false;
    }

    /// DOM method returns null,
    XmlString baseURI()
    {
        return null;
    }

    //uint compareDocumentPosition(Node other){ return DocumentPositionFlag.DISCONNECTED; }

    /// DOM method returns null,
    XmlString getTextContent()
    {
        return null;
    }

    /// not implemented here
    void setTextContent(XmlString textContent)
    {
        notImplemented("textContent");
    }

    bool isSameNode(Node other)
    {
        return false;
    }

    /// not implemented here
    string lookupPrefix(XmlString namespaceURI)
    {
        notImplemented("lookupPrefix");
        return null;
    }

    /// not implemented here
    bool isDefaultNamespace(XmlString namespaceURI)
    {
        notImplemented("isDefaultNamespace");
        return false;
    }

    /// not implemented here
    string lookupNamespaceURI(XmlString prefix)
    {
        notImplemented("lookupNamespaceURI");
        return null;
    }

    /// not implemented here
    bool isEqualNode(Node arg)
    {
        return false;
    }

    /// not implemented here
    Object setUserData(XmlString key, Object data)
    {
        notImplemented("setUserData");
        return null;
    }

    /**
	* Retrieves the object associated with key, last set using setUserData.
	* Params:
	* key = The key the object is associated to.
	* Returns: the object associated to the given
	*   key on this node, null
	*
	*/
    /// not implemented, returns null
    Object getUserData(XmlString key)
    {
        return null;
    }

    /// not implemented here
    void setParentNode(Node n)
    {
        notImplemented("setParentNode");
    }

    /// returns null
    Node getParentNode()
    {
        return null;
    }
	/// Object.toString is fixed as string return type
	XmlString toXmlString()
	{
		return ( getNodeType()==NodeType.Element_node) ? getTextContent() :  getNodeValue();
	}
}

/// Wraps naked Node[] as class.
class NodeList
{

    Node[]		items_;
public:
    @property final uintptr_t getLength()
    {
        return items_.length;
    }

    final Node item(uintptr_t ix)
    {
        return items_[ix];
    }

    /// constructor
    this()
    {
    }
    /// constructor
    this(Node[] nlist)
    {
        items_ = nlist;
    }
    /// constructor
    this(Node link)
    {
        addLinkList(link);
    }
    /// append all next sibling nodes
    void addLinkList(Node link)
    {
        auto app = appender(items_);

        while(link !is null)
        {
            app.put(link);
            link = link.getNextSibling();
        }
        items_ = app.data();
    }

    /// apply delegate to each member
    int opApply(scope int delegate(ref Node) dg)
    {
        for(size_t ix = 0; ix < items_.length; ix++)
        {
            int result = dg(items_[ix]);
            if (result)
                return result;
        }
        return 0;
    }

    /// support array append
    void opCatAssign(Node[] nlist)
    {
        items_ ~= nlist;
    }

    /// support single append
    void opCatAssign(Node n)
    {
        items_ ~= n;
    }

    /// set length to 0
    void clear()
    {
        items_.length = 0;
    }

    /// Assign as one node length.
    void assignOne(Node n)
    {
        items_.length = 1;
        items_[0] = n;
    }

    /// index support
	Node opIndex(size_t ix)
    {
        return items_[ix];
    }

    /// raw access
    Node[] items()
    {
        return items_;
    }

    /// length property
    @property const size_t length()
    {
        return items_.length;
    }

    /// assign raw array
    void setItems(Node[] all)
    {
        items_ = all;
    }

}


static void NodeShellSort(Node[] nodes, NodeCompareFn cmp)
{

	auto limit = nodes.length;
	if (limit < 2)
		return;
	static immutable int[] gapseq =
	[1391376, 463792, 198768, 86961, 33936, 13776, 4592,
	1968, 861, 336, 112, 48, 21, 7, 3, 1];

	for(uint gapix = 0; gapix < gapseq.length; gapix++)
	{
		const int gap = gapseq[gapix];

		for (int i = gap; i < limit; i++)
		{
			Node v = nodes[i];
			int j = i;
			while (j >= gap)
			{
				Node c = nodes[j-gap];
				if (cmp(c,v) > 0)
				{
					nodes[j] = c;
					j = j-gap;
				}
				else
					break;
			}
			nodes[j] = v;
		}
	}
}



/// A little factory class
class DOMImplementation
{


    /// Make DocumentType node
    DocumentType createDocumentType(XmlString qualName, XmlString publicId, XmlString systemId)
    {
        DocumentType dtype = new DocumentType(qualName);
        dtype.publicId = publicId;
        dtype.systemId = systemId;
        return dtype;

    }
    /// Make a Document
    Document createDocument(XmlString namespaceURI, XmlString qualName, DocumentType docType)
    {
        XmlString name = (namespaceURI !is null)? concats(namespaceURI, ":", qualName) : qualName;
        DocumentType dtype = (docType is null) ? null : cast(DocumentType) docType;

        Document doc = new Document(dtype,name);
        doc.setImplementation(this);

        return doc;
    }

    /// Not implemented
    bool hasFeature(string feature, string versionStr)
    {
        notImplemented("hasFeature");
        return false;
    }
}

import std.variant;

/// Only works for setting the DOMErrorHandler at present
class DOMConfiguration
{
    Document ownerDoc_;
    Variant[string]	map_;

    /*
    The parameter can be set, if exists in the map_, and
    the value type is the same as the Variant type stored in the map?
    */
public:
    this(Document doc)
    {
        ownerDoc_ = doc;
    }
    /// DOM interface using std.variant
    Variant getParameter(string name)
    {
        return map_[name];
    }

    void setDefaults()
    {
        setParameter("namespaces",Variant(true));
        setParameter("namespace-declarations",Variant(true));

        setParameter("canonical-form",Variant(false));
        setParameter("cdata-sections",Variant(true));
        setParameter("check-character-normalization",Variant(false));
        setParameter("comments",Variant(true));
        setParameter("entities",Variant(true));
        Variant eh = new DOMErrorHandler();
        setParameter("error-handler",eh);
        setParameter("edition",Variant(cast(uint)5));

    }
    /// DOM interface using std.variant
    bool canSetParameter(string name, Variant value)
    {
        // a real implementation would be complex, and check the value
        return (name in map_) !is null;
    }
    /// get names of accessible parameters
    StringList!char getParameterNames()
    {
        return new StringList!char(map_.keys());
    }
    /// DOM interface using std.variant
    void setParameter(string name, Variant value)
    {
        map_[name] = value;
        ownerDoc_.configChanged(name);
    }

};

/// DOM accessible parts of DTD, just entities and notations.
class DocumentType  : ChildNode
{
package:
    XmlString	publicId;
    XmlString	systemId;

    NamedNodeMap entities_;
    NamedNodeMap notations_;
    XmlString internal_;

public:
	version(GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
	}
    override const NodeType getNodeType()
    {
        return NodeType.Document_type_node;
    }

	void setSource(XmlString pubid, XmlString sysid)
	{
		publicId = pubid;
		systemId = sysid;
	}

	override void explode()
	{
		entities_.explode();
		notations_.explode();
	}

    XmlString getPublicId()
    {
        return publicId;
    }
    XmlString getSystemId()
    {
        return systemId;
    }
    /// The name isn't used much, but maybe could use for hash identity.
    this(XmlString name)
    {
        id_ = name;
        entities_ = new NamedNodeMap();
        notations_ = new NamedNodeMap();
		version(GC_STATS)
			gcStatsSum.inc();

    }
    /// what good is this?
    XmlString getName()
    {
        return id_;
    }

    /// what good is this?
    XmlString getInternalSubset()
    {
        return internal_;
    }

    override XmlString getNodeName()
    {
        return id_;
    }

    /// Node map for notations
    NamedNodeMap getNotations()
    {
        return notations_;
    }
    /// Node map for entities
    NamedNodeMap getEntities()
    {
        return entities_;
    }

}

/// Not yet used
class EntityReference : ChildNode
{
public:
    this(XmlString id)
    {
        super(id);
    }
    override XmlString getNodeName()
    {
        return id_;
    }
    override const NodeType getNodeType()
    {
        return NodeType.Entity_Reference_node;
    }
}

/// Parsed and in DOM but not used.
class ProcessingInstruction : ChildNode
{
    XmlString   data_;
public:
    this(XmlString target, XmlString data)
    {
        super(target);
        data_ = data;
    }
    this()
    {
    }
    override XmlString getNodeValue()
    {
        return id_;
    }
    override const NodeType getNodeType()
    {
        return NodeType.Processing_Instruction_node;
    }
    XmlString getTarget()
    {
        return id_;
    }
    override XmlString getNodeName()
    {
        return id_;
    }

    XmlString getData()
    {
        return data_;
    }

    void setData(XmlString data)
    {
        data_ = data;
    }


    override XmlString toXmlString()  const
    {
        return XMLOutput!T.makeXmlProcessingInstruction(id_,data_);
    }

}

/// Essential DOM component
class Document  : Node
{
    DocumentType	dtd_;
    Element			docElement_;
    Element			rootElement_; // for comments, processing instructions.

    DOMConfiguration		config_;
    DOMImplementation		implementation_;
    DOMErrorHandler			errorHandler_;

    XmlString		version_;
    double			versionNum_;
    uint			edition_ = 5;
    XmlString		encoding_;
    XmlString		inputEncoding_;
    bool			standalone_;
    bool			check_;
    bool			namespaceAware_;
    XmlString		uri_;
	uintptr_t		refcount_;
public:
	version(GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
    this()
    {
        init("NoName");

    }

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();

	}
	/// Initialise with a name, but this does not make a Document Element.
    this(XmlString name)
    {
        init(name);
    }

	/// Initialise with a Document Element
    this(Element root)
    {
        init("NoName");
        appendChild(root);
    }
    /// Supplied DTD
    this(DocumentType docType,XmlString name)
    {
        init(name);
        dtd_ = docType;
    }

	/// Part of DOM
    override const NodeType getNodeType()
    {
        return NodeType.Document_node;
    }

    /// Document property
    void setInputEncoding(const XmlString value)
    {
        inputEncoding_ = value;
    }
    /// Document property
    void setEncoding(const XmlString value)
    {
        encoding_ = value;
    }
    /// Document property
    bool getStrictErrorChecking()
    {
        return check_;
    }
    void setStrictErrorChecking(bool val)
    {
        check_ = val;
    }

	void incRef()
	{
		refcount_++;
	}

	void decRef()
	{
		if (refcount_ == 1)
			explode();
		else
			refcount_--;
	}
    /// Document property, not available yet
    DocumentType getDoctype()
    {
        return dtd_;
    }

    /// Document property, not available yet
    XmlString getDocumentURI()
    {
        return uri_;
    }

    /// DOM document data root Element
    Element getDocumentElement()
    {
        return docElement_;
    }

    /// Used to get and set parameters in the document.
    DOMConfiguration getDomConfig()
    {
        return config_;
    }

    /// Not used yet
    DOMImplementation getImplementation()
    {
        return implementation_;
    }

    /// Document property
    XmlString getXmlEncoding()
    {
        return encoding_;
    }

    /// Document property
    XmlString getInputEncoding()
    {
        return inputEncoding_;
    }

    /// DOM property: dependency on external documents
    void setXmlStandalone(bool standalone)
    {
        standalone_ = standalone;
    }

    /// DOM property: dependency on external documents
    bool getXmlStandalone()
    {
        return standalone_;
    }

    /// Document property
    void setXmlVersion(XmlString xmlVersion)
    {
        version_ = xmlVersion;
    }

    XmlString getXmlVersion()
    {
        return version_;
    }

    /// Not implemented yet
    Element getElementById(XmlString id)
    {
        return null;
    }

    void configChanged(string param)
    {
        Variant v = config_.getParameter(param);

        if (param ==  "error-handler")
        {
            DOMErrorHandler* p = v.peek!(DOMErrorHandler); // whohoo
            errorHandler_ = (p is null) ? null : *p;
        }
        else if (param == "namespaces")
        {
            namespaceAware_ = v.get!(bool);
        }
        else if (param == "edition")
        {
            edition_ = v.get!(uint);
        }
    }

    Node  adoptNode(Node source)
    {
        NodeType ntype = source.getNodeType();
        switch(ntype)
        {
        case  NodeType.Element_node:

            Element xe = cast(Element)(source);
            xe.setDocument(this);
            xe.setParentNode(docElement_);
            this.setOwner(docElement_);
            return source;
        default:
            break;
        }
        DOMClassException("unsupported node type adoptNode: ",typeid(source).name);
        return null;
    }
    /// support ~=
    void opCatAssign(Element e)
    {
        appendChild(e);
    }

    /// Child must be the only Element or DocType node, comment or processing instruction.
    override Node appendChild(Node newChild)
    {
        NodeType ntype = newChild.getNodeType();
        switch(ntype)
        {
        case  NodeType.Element_node:
        {
            Element xe = cast(Element)(newChild);
            if (docElement_ is null)
            {
                xe.setDocument(this);
                docElement_ = xe;
                rootElement_.appendChild(docElement_);

                return newChild;
            }
            else
                docElement_.appendChild(xe);

            //throw new DOMFail("Already have document element");
        }
        break;
        case  NodeType.Comment_node:
        {
            Comment cmt = cast(Comment)(newChild);
            rootElement_.appendChild(cmt);
            return newChild;
        }
        case  NodeType.Processing_Instruction_node:
        {
            ProcessingInstruction xpi =  cast(ProcessingInstruction)(newChild);
            if (xpi !is null)
            {
                rootElement_.appendChild(xpi);
                return newChild;
            }
        }
        break;
        case NodeType.Document_type_node:
        {
            DocumentType dt = cast(DocumentType)(newChild);
            if (dt !is null)
            {
                if (dtd_ !is null)
                    throw new DOMFail("Already have DocumentType node");

                dtd_ = dt;
                rootElement_.appendChild(dt);
                return newChild;
            }
        }
        break;

        default:
            DOMClassException("Document.appendChild: type not supported ",typeid(newChild).name);
            break;
        }
        return null;
    }

    /// Not useful or tested yet
    Node importNode(Node n, bool deep)
    {
        NodeType ntype = n.getNodeType();
        if (ntype == NodeType.Element_node)
        {
            Element en = cast(Element)(n);
            ElementNS ens = cast(ElementNS)(en);
            if (ens !is null)
            {
                ElementNS ecopyNS = cast(ElementNS)(createElementNS(ens.getNamespaceURI(), ens.getNodeName()));
                importAttributesNS(ens, ecopyNS);
                adoptNode(ecopyNS);
                return ecopyNS;
            }

        }
        DOMClassException("importNode: unsupported type ",typeid(n).name);
        return null;
    }

    /**
    	Not tested or useful yet.
    	Rename one of the documents nodes.
    	The facility to rename a node, is not in the actual Node interface?
    	The local name can be a prefix:name.
    */
    Node renameNode(Node n, XmlString uri, XmlString local)
    {
        NodeType ntype = n.getNodeType();
        switch(ntype)
        {
        case NodeType.Element_node:
        {
            ElementNS en =  cast(ElementNS)( n );
            if (en is null || en.getOwnerDocument() != this)
            {
                throw new DOMFail("renameNode: Not owned by this document");
            }
            en.setIdentity(uri, local);
            return en;
        }

        case NodeType.Attribute_node:
        default:
            break;
        }

        DOMClassException("renameNode: Not supported for ",typeid(n).name);
        return n;
    }

    /// Change owner of the node and its element children to be this document
    int setOwner(Node n)
    {
        // set every child of n to have this as owner?
        Element en = cast(Element)(n);

        int setNodeOwner(Node n)
        {
            Element c = cast(Element) n;
            if (c !is null)
                c.setDocument(this);

            return 1;
        }

        if (en !is null && en.hasChildNodes())
        {
            en.forEachChild(&setNodeOwner);
        }
        return 0;
    }


    /// not implemented properly yet
    void  importAttributesNS(Element src, Element dest)
    {
        int copyAttr(Node n)
        {
            Attr atr = cast(Attr) n;
            if(atr !is null)
                dest.setAttribute(atr.getName(), atr.getValue());
            return 1;
        }

        src.forEachAttr(&copyAttr);
    }

    private void init(XmlString name)
    {
		version(GC_STATS)
			gcStatsSum.inc();
        id_ = name;

        standalone_ = true;
        check_ = false; //?
        versionNum_ = 1.0;
        version_ = "1.0";
        encoding_ = "UTF-8";
        inputEncoding_ = encoding_;//?
        config_ = new DOMConfiguration(this);
        config_.setDefaults();
        docElement_ = null;
        rootElement_ = new Element("_root");
        rootElement_.setDocument(this);
        implementation_= null;
        errorHandler_ = null;
        namespaceAware_ = true;
    }

    const void printOut(StringPutDg dg, uint indent = 2)
    {
        printDocument(cast(Document) this, dg, indent);
    }

    const XmlString[] pretty(uint indent)
    {
        Buffer!XmlString app;
        ImmuteAlloc!T ialloc;

        void addstr(const(T)[] s)
        {
            app.put(ialloc.alloc(s));
        }

        printDocument(cast(Document) this, &addstr, indent);

        return app.take;
    }

    void setImplementation(DOMImplementation idom)
    {
        implementation_ = idom;
    }

	void unlink()
	{
		dtd_ = null;
		docElement_= null;
		rootElement_= null; // for comments, processing instructions.
		config_= null;
		implementation_= null;
		errorHandler_= null;
	}

	/// tear everything apart for attempts at garbage collection
	override void explode()
	{
		auto elem = getRootElement();
		rootElement_ = null;
		elem.explode();
		unlink();
		super.explode();
	}
    package Element getRootElement()
    {
        return rootElement_;
    }

    /// DOM node constructor for this document
    Attr
    createAttribute(XmlString name)
    {
        if (namespaceAware_)
            return new AttrNS(name);
        else
            return new Attr(name);
    }

    /// DOM node constructor for this document
    Attr
    createAttributeNS(XmlString uri, XmlString qname)
    {
        AttrNS result = new AttrNS(uri,qname);
        return result;
    }

    /// DOM node constructor for this document
    CDATASection
    createCDATASection(XmlString data)
    {
        CDATASection result = new CDATASection(data);
        //result.setDocument(this);
        return result;
    }

    /// DOM node constructor for this document
    Comment
    createComment(XmlString data)
    {
        Comment result = new Comment(data);
        //result.setDocument(this);
        return result;
    }
    /// DOM node constructor for this document
    Element
    createElement(XmlString tagName)
    {
        if (namespaceAware_)
            return new ElementNS(tagName);
        else
            return new Element(tagName);

    }
    /// DOM node constructor for this document
    Element
    createElementNS(XmlString uri, XmlString local)
    {
        ElementNS result = new ElementNS(uri, local);
        //result.setDocument(this);
        return result;
    }
    /// DOM node constructor for this document
    EntityReference
    createEntityReference(XmlString name)
    {
        EntityReference result = new EntityReference(name);
        //result.setDocument(this);
        return result;

    }
    /// DOM node constructor for this document
    Text
    createTextNode(XmlString data)
    {
        Text result = new Text(data);
        //result.setDocument(this);
        return result;
    }
    /// DOM node constructor for this document
    ProcessingInstruction
    createProcessingInstruction(XmlString target, XmlString data)
    {
        ProcessingInstruction result = new ProcessingInstruction(target, data);
        //result.setDocument(this);
        return result;
    }

    /// List  nodes without breaking up relationships.
    NodeList
    getElementsByTagName(XmlString name)
    {
        if (docElement_ !is null)
            return docElement_.getElementsByTagName(name);
        else
            return new  NodeList();
    }
    /// List  nodes without breaking up relationships.
    NodeList
    getElementsByTagNameNS(XmlString uri, XmlString local)
    {
        if (docElement_ is null)
            return docElement_.getElementsByTagNameNS(uri,local);
        else
            return new NodeList();
    }

}

/** Not really used yet. Not sure what its good for.
	Holds a linked list of nodes.
*/
class DocumentFragment : Node
{
protected:
    ChildList children_;
public:
    /// empty by nulling
    void clear()
    {
        children_.firstChild_ = null;
        children_.lastChild_ = null;
    }

    /// set the list from first to last
    void set(ChildNode first, ChildNode last)
    {
        children_.firstChild_ = first;
        children_.lastChild_ = last;
    }

    /// DOM method
    override Node getFirstChild()
    {
        return children_.firstChild_;
    }

    /// DOM method
    override Node getLastChild()
    {
        return children_.lastChild_;
    }
    /// DOM method
    override NodeList getChildNodes()
    {
        Node[] items;
        Node   n = children_.firstChild_;
        while (n !is null)
        {
            items ~= n;
            n = n.getNextSibling();
        }
        return new NodeList(items);
    }
    /// Throws exception if child is attached elsewhere
    override Node  appendChild(Node newChild)
    {
        ChildNode xnew = cast(ChildNode) newChild;
        if (xnew is null)
            throw new DOMFail("null child to appendChild");

        children_.linkAppend(xnew);
        xnew.parent_ = this;
        // ownerDoc of elements?
        return newChild;
    }
}



/**
	Java DOM class semblance, that stores attributes for an Element,
	Implementation uses a simple list in triggered sort order.
*/
class NamedNodeMap
{

private:
    NodeCompareFn	cmp_;
    Node[]		items_;
    bool			sorted_;
public:

    static int CompareNodes(Node n1, Node n0)
    {
        return cmp(n1.getNodeName(), n0.getNodeName());
    }


    this()
    {
        cmp_ = &CompareNodes;
    }

    /// method
    alias length getLength;

    /// property
    @property  final size_t length()
    {
        return items_.length;
    }

    /// method
    final Node getNamedItem(XmlString name)
    {
        auto ix = findNameIndex(name);
        if (ix >= 0)
            return items_[ix];
        else
            return null;
    }

    /// method
    final Node getNamedItemNS(XmlString nsURI, XmlString local)
    {
        auto ix = findNSLocalIndex(nsURI, local);
        if (ix >= 0)
            return items_[ix];
        else
            return null;
    }

    /// Access may resort the data, if insertion occurred.
    final Node item(uintptr_t ix)
    {
        if (!sorted_)
            sortMe();
        return items_[ix];
    }

    /// Delegate visitor
    final int forEachNode(NodeVisitFn dg)
    {
        if (!sorted_)
            sortMe();
        for(size_t ix = 0; ix < items_.length; ix++)
        {
            int result = dg(items_[ix]);
            if (result)
                return result;
        }
        return 0;
    }
    /// method
    int opApply(scope int delegate(ref Node n) doit)
    {
        if (!sorted_)
            sortMe();
        foreach(n ; items_)
        {
            int result = doit(n);
            if (result != 0)
                return result;
        }
        return 0;
    }

	/**
	Pre-emptive strike to devastate object, and possibly delete at same tile.
	Destructor, must call with del false, and ideally explode can tell,
	if its job is already done.
	*/
	void explode()
	{
		auto oldItems = items_;
		items_ = [];

		foreach(n ; oldItems)
		{
			n.explode();
		}
	}

    private void erase(size_t ix)
    {
        auto nlen = items_.length;
        if (ix+1 == nlen)
        {
            items_[ix] = null;
            items_ = (items_.ptr)[0..ix];
            return;
        }
        memmove(cast(void*) &items_[ix], cast(const(void*)) &items_[ix+1], (nlen - ix-1) * Node.sizeof);
        nlen -= 1;
        items_[nlen] = null;
        items_ = (items_.ptr)[0..nlen];
    }

    /// Node removal
    Node removeNamedItem(XmlString name)
    {
        Node result;
        auto ix = findNameIndex(name);
        if (ix >= 0)
        {
            result = items_[ix];
            erase(ix);
        }
        return result;
    }

    /// Node removal, this is untried
    final Node removeNamedItemNS(XmlString nsURI, XmlString local)
    {
        Node result;
        auto ix = findNSLocalIndex(nsURI, local);
        if (ix >= 0)
        {
            result = items_[ix];
            erase(ix);
            sorted_ = false;
        }
        return result;
    }

    /// D style access support
    final Node opIndex(size_t ix)
    {
        if (!sorted_)
            sortMe();
        return items_[ix];
    }

    final Node opIndex(const(T)[] name)
    {
        auto ix = findNameIndex(name);
        if (ix >= 0)
            return items_[ix];
        else
            return null;
    }

    /// return replaced node or null
    final Node setNamedItem(Node n)
    {
        auto nodeName = n.getNodeName();
        Node result = null;

        auto ix = findNameIndex(nodeName);
        if (ix >= 0)
        {
            // replace
            result = items_[ix];
            items_[ix] = n;
        }
        else
        {
            // append unsorted
            items_ ~= n;
            sorted_ = false;
        }
        return result;
    }

    /// return replaced node or null
    final Node setNamedItemNS(Node n)
    {
        Node result = null;
        auto ix = findNSLocalIndex(n.getNamespaceURI(), n.getLocalName());
        if (ix >= 0)
        {
            result = items_[ix];
            items_[ix] = n;
        }
        else
        {
            // append unsorted
            items_ ~= n;
        }
        sorted_ = false;
        return result;
    }

	final void destroy()
	{
		if (items_ !is null)
			items_.destroy();
		items_ = null;
	}
private:

    void sortMe()
    {
        sorted_ = true;
		if (items_.length > 1)
			NodeShellSort(items_, cmp_);
    }
    /// return -1 if not found
    intptr_t findNameIndex(const(T)[] name)
    {
        if (!sorted_)
            sortMe();
        auto bb = cast(size_t)0;
        auto ee = items_.length;
        while (bb < ee)
        {
            auto m = (ee + bb) / 2;
            Node n = items_[m];
            auto nodeName = n.getNodeName();
            int cresult = cmp(name,nodeName);
            if (cresult > 0)
                bb = m+1;
            else if (cresult < 0)
                ee = m;
            else
                return cast(int) m;
        }
        return -1;
    }

    intptr_t findNSLocalIndex(XmlString uri, XmlString lname)
    {
        if (uri.length > 0)
        {
            for(size_t i = 0; i < items_.length; i++)
            {
                Node n = items_[i];
                auto nURI = n.getNamespaceURI();
                auto nLocal = n.getLocalName();
                if ((nURI.ptr) && (nLocal.ptr))
                {
                    int cURI = cmp(nURI,uri);
                    if (cURI == 0)
                    {
                        int cLocal = cmp(nLocal,lname);
                        if (cLocal==0)
                            return i;
                    }
                }
            }
        }
        else
        {
            for(size_t i = 0; i < items_.length; i++)
            {
                Node n = items_[i];
                auto nURI = n.getNamespaceURI();
                auto nLocal = n.getLocalName();
                if ((nURI.ptr) && (nLocal.ptr))
                {
                    int cLocal = cmp(nLocal,lname);
                    if (cLocal==0)
                        return i;
                }
            }
        }
        return -1;
    }
}

/// abstract class, has a parent and linked sibling nodes
abstract class ChildNode : Node
{
protected:
    Node				parent_;
    ChildNode			next_;
    ChildNode			prev_;
    //Document			ownerDoc_;
public:

	/// For shuffling smallish numbers of nodes.s

    this(XmlString id)
    {
        super(id);
    }
    this()
    {
    }

    /// get all children as array of Node
    static Node[] getNodeList(ChildNode n)
    {
        if (n is null)
            return null;

        Node[] items;
        auto app = appender(items);
        while(n !is null)
        {
            app.put(n);
            n = n.next_;
        }
        return app.data();
    }
    /// ChildNode siblings
    override Node getPreviousSibling()
    {
        return prev_;
    }
    /// ChildNode siblings
    override Node getNextSibling()
    {
        return next_;
    }

    /// set same parent of all linked children
    static void setParent(ChildNode n, Node parent)
    {
        while(n !is null)
        {
            n.parent_ = parent;
            n = n.next_;
        }
    }
    /// set parent
    override void setParentNode(Node p)
    {
        parent_ = p;
    }

    /// get parent
    override Node getParentNode()
    {
        return parent_;
    }

    /** Only Elements actually hold a reference to the ownerDocument.
    	Other nodes can refer via the parent Element.
    */
    override Document getOwnerDocument()
    {
        if (parent_ !is null)
        {
            Element pe = cast(Element) parent_;
            if (pe !is null)
                return pe.getOwnerDocument();
        }
        return null;
    }
    //@property final Node getParentNode() { return lnk.parent_;}
    /*
    void setDocument(Document d)
    {
    	ownerDoc_ = d;
    }

    */
}

/// Linking functions to put in a class.
struct ChildList
{
    ChildNode firstChild_;
    ChildNode lastChild_;

	/// Remove all links at once. Let the GC sort this out!
	void removeAll()
	{
		firstChild_ = null;
		lastChild_ = null;
	}

	bool empty()
	{
		return((firstChild_ is null) && (lastChild_ is null));
	}

    /// remove
    void removeLink(ChildNode ch)
    {
        ChildNode prior = ch.prev_;
        ChildNode post = ch.next_;
        if (prior !is null)
        {
            prior.next_ = ch.next_;
        }
        else
        {
            firstChild_ = ch.next_;
        }
        if (post !is null)
        {
            post.prev_ = ch.prev_;
        }
        else
        {
            lastChild_ = ch.prev_;
        }
		ch.prev_ = null;
		ch.next_ = null;
    }

    /// add
    void  linkAppend(ChildNode cn)
    {
        if (cn.parent_ !is null)
            throw new DOMFail("appended child already has a parent");

        ChildNode prior = lastChild_;
        if (prior is null)
        {
            firstChild_ = cn;
            cn.prev_ = null;
        }
        else
        {
            lastChild_.next_ = cn;
            cn.prev_ = lastChild_;
        }
        cn.next_ = null;
        lastChild_ = cn;
    }

    /// insert a lot
    void chainAppend(ChildNode chainBegin, ChildNode chainEnd)
    {
        ChildNode prior = lastChild_;
        if (prior is null)
        {
            firstChild_ = chainBegin;
            chainBegin.prev_ = null;
        }
        else
        {
            lastChild_.next_ = chainBegin;
            chainBegin.prev_ = lastChild_;

        }
        chainEnd.next_ = null;
        lastChild_ = chainEnd;
    }

    /// only for non-null xref, which must be already a child
    void insertChainBefore(ChildNode chainBegin, ChildNode chainEnd, ChildNode xref)
    {
        assert(xref !is null);
        ChildNode prior = xref.prev_;
        if (prior is null) // insert is before first link
        {
            firstChild_ = chainBegin;
        }
        chainBegin.prev_ = prior;
        xref.prev_ = chainEnd;
        chainEnd.next_ = xref;
    }
    /// only for non-null cref, which must be already a child
    void linkBefore(ChildNode add, ChildNode cref)
    {
        assert(cref !is null);

        ChildNode prior = cref.prev_;
        if (prior is null)
        {
            firstChild_ = add;
        }
        else
        {
            prior.next_ = add;
        }
        add.prev_ = prior;
        add.next_ = cref;
        cref.prev_ = add;
    }
}

/// The Identity is duel, set by uriNS and localName.  The getNodeName returns the prefix:localName.
/// Set local name is assumed to be actually prefix:localName, or just localName.
/// prefix is set by the nearest URI binding up the tree, once inserted in a document.
class ElementNS : Element
{
protected:
    XmlString uriNS_;
    XmlString localName_;



public:
    /// construct
    this(XmlString  tag)
    {
        setIdentity(null, tag);
    }
    /// construct
    this()
    {
    }

    /** Contradicted constructor for Element with same arguments
        If name is localName, then will need to lookup URI local prefix in tree to make id?
    	Find parent node which has xmlns:<prefix> = URI. But at construction do not have parent.
    	So at least a check takes place when adding to document.
    */
    this(XmlString uri, XmlString name)
    {
        setIdentity(uri, name);
    }
    /// return associated URI
    override XmlString getNamespaceURI()
    {
        return uriNS_;
    }

    /// The local name is after a ':', or the full name if no ':'
    override XmlString getLocalName()
    {
        return localName_;
    }

    /// Get local prefix, which might be zero length
    override XmlString getPrefix()
    {
        auto poffset = id_.length - localName_.length;
        return  (poffset > 0) ? id_[0..poffset-1] : "";
    }
    /// DOM attribute management
    override void setAttribute(XmlString name, XmlString value)
    {
        Attr na = new AttrNS(name);
        na.setValue(value);
        setAttributeNode(na);
    }
    void setIdentity(XmlString nsURI, XmlString name)
    {
        id_ = name;
        uriNS_ = nsURI;
        auto pos =  std.string.indexOf(id_,':');
        localName_ = (pos >= 0) ? id_[pos+1..$] : id_;
    }

    void setURI(XmlString nsURI)
    {
        uriNS_ = nsURI;
    }
}


/// Wrap Element, and pretend attributes are set[] and get[] by string. Not very interesting
struct ElemAttributeMap
{
    private Element e_;

    this(Element e)
    {
        e_ = e;
    }
    ///  map[string] = support
    void opIndexAssign(XmlString value, XmlString key)
    {
        e_.setAttribute(key,value);
    }

    /// support = map[string]
    XmlString opIndex(XmlString key)
    {
        return e_.getAttribute(key);
    }


};

/// Binds the document tree together.
class Element :  ChildNode
{
	version(GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
protected:
    NamedNodeMap		attributes_;
    ChildList			children_;
    Document			ownerDoc_;
public:
    /// method
    override Document getOwnerDocument()
    {
        return ownerDoc_;
    }
    /// construct
    this(XmlString  tag)
    {
        super(tag);
		version (GC_STATS)
			gcStatsSum.inc();
    }
    /// construct
    this()
    {
 		version (GC_STATS)
			gcStatsSum.inc();
	}
	/**
		If object is left to garbage collector, explode(false)
		should further dismember in safety, or do nothing.
	*/
	~this()
	{
		//explode(false);
 		version (GC_STATS)
			gcStatsSum.dec();
	}
    /// construct, with single child of text content
    this(XmlString tag, XmlString content)
    {
        super(tag);
        auto txt = new Text(content);
        appendChild(txt);
		version (GC_STATS)
			gcStatsSum.inc();
    }
    /// method
    override bool hasAttributes()
    {
        return attributes_ is null ? false : attributes_.getLength > 0;
    }
    /// returns NodeType.Element_node
    override const NodeType getNodeType()
    {
        return NodeType.Element_node;
    }

    /// method
    override bool	 hasChildNodes()
    {
        return children_.firstChild_ !is null;
    }

	void countLeaves(ref ulong count)
	{
		count++;
		if (attributes_ !is null)
			count += (attributes_.getLength());

		auto ch = this.getFirstChild();
		while (ch !is null)
		{
			auto elem = cast(Element) ch;
			ch = ch.getNextSibling();
			if (elem !is null)
				elem.countLeaves(count);
			else
				count++;
		}
	}
    /// return children as array
    ChildNode[] childNodes()
    {
        ChildNode[] result;
        ChildNode cn = children_.firstChild_;
        size_t len = 0;
        while(cn !is null)
        {
            cn = cn.next_;
            len += 1;
        }
        if (len > 0)
        {
            result.length = len;
            cn = children_.firstChild_;
            size_t ix = 0;
            while(cn !is null)
            {
                result[ix++] = cn;
                cn = cn.next_;
            }
        }
        return result;
    }
    /// Get attributes interface
    override NamedNodeMap getAttributes()
    {
        return attributes_;
    }

    /// Set and get all the attributes using whatever AttributeMap is
    void setAttributes(AttributeMap!T amap)
    {
        foreach(k,v ; amap)
        {
            setAttribute(k,v);
        }
    }

    /// DOM method
    @property ElemAttributeMap attributes()
    {
        return ElemAttributeMap(this);
    }
    /*

    */
    /// method
    Attr getAttributeNode(XmlString name)
    {
        if (attributes_ is null)
            return null;
        Node n = attributes_.getNamedItem(name);
        return (n is null) ? null : cast(Attr)n;
    }

    /// This could be used to add all the attributes to a NodeList
    void addAttributes(NodeList nlist)
    {
        auto alen = attributes_.getLength;
        for(uintptr_t i = 0; i < alen; i++)
            nlist ~= attributes_[i];
    }

    /// This could be used to add all the children of this node to a NodeList
    void addChildTags(NodeList nlist)
    {
        if (children_.firstChild_ !is null)
        {
            Node[] nodes = ChildNode.getNodeList(children_.firstChild_);
            nlist ~= nodes;
        }
    }
    /// Add all the child Elements with name to the NodeList argument
    void addChildTags(XmlString name, NodeList nlist)
    {
        ChildNode link	 = children_.firstChild_;

        while (link !is null)
        {
            Element e = cast(Element) link;
            if (e !is null)
            {
                if (cmp(name,e.getTagName())==0)
                    nlist ~= e;
            }
            link = link.next_;
        }
    }

    /// Returns a node list with all the named child elements
    NodeList  getElementsByTagName(XmlString name)
    {
        NodeList result = new NodeList();
        addChildTags(name, result);
        return result;
    }
    /// Namespace implementation has been dropped for now
    NodeList getElementsByTagNameNS(XmlString uri, XmlString local)
    {
        /// this is surely wrong
        XmlString name = (uri is null) ? local : concats(uri ,":" ,local);
        return getElementsByTagName(name);
    }
    // return all element nodes
    NodeList getChildElements()
    {
        Node[] result;
        ChildNode ch = children_.firstChild_;
        while (ch !is null)
        {
            if (ch.getNodeType() == NodeType.Element_node)
                result ~= ch;
            ch = ch.next_;
        }
        return new NodeList(result);
    }

    /// method
    bool hasAttribute(XmlString name)
    {
        return (attributes_ is null) ? false
               : (attributes_.getNamedItem(name) !is null);
    }
    /// method
    bool  hasAttributeNS(XmlString uri, XmlString local)
    {
        return (attributes_ is null) ? false
               : (attributes_.getNamedItemNS(uri, local) !is null);
    }
    /// Return string value for the named attribute.
    XmlString getAttribute(XmlString name)
    {
        if (attributes_ is null)
            return null;

        Node n = attributes_.getNamedItem(name);
        return ( n is null) ? null : (cast(Attr)n).getValue();
    }
    /// method to be fixed
    XmlString getAttributeNS(XmlString uri, XmlString local)
    {
        if (attributes_ is null)
            return null;
        Node n = attributes_.getNamedItemNS(uri, local);
        return ( n is null) ? null :(cast(Attr)n).getValue();
    }
    /// to be fixed
    Attr getAttributeNodeNS(XmlString uri, XmlString local)
    {
        if (attributes_ is null)
            return null;
        Node n = attributes_.getNamedItemNS(uri, local);
        return ( n is null) ? null : cast(Attr) n;
    }
    /// method
    override XmlString getNodeName()
    {
        return id_;
    }

    XmlString  getTagName()
    {
        return id_;
    }
    /// method
    override NodeList getChildNodes()
    {
        return new NodeList(ChildNode.getNodeList(children_.firstChild_));
    }
    int forEachAttr( NodeVisitFn  dg)
    {
        return (attributes_ is null) ? 0 : attributes_.forEachNode(dg);
    }
    int forEachChild(NodeVisitFn dg)
    {
        ChildNode link = children_.firstChild_;
        int result = 0;
        while (link !is null)
        {
            result = dg(link);
            if (result)
                return result;
            link = link.next_;
        }
        return result;
    }
	/// Brutal replacement of all children with single text node
	override void setTextContent(XmlString txt)
	{
		children_.removeAll();
		if (txt.length > 0)
			appendChild(new Text(txt));
	}
    ///Recursive on Text-like data.  Has no implementation of isTextNodeWhiteSpace
    override XmlString getTextContent() const
    {
        Buffer!T	app;

        auto xn = cast(ChildNode) children_.firstChild_; // trouble with const
        if (xn is null)
            return null;

        do
        {
            auto n = xn;
            switch(n.getNodeType())
            {
				//case NodeType.Comment_node://
				//case NodeType.Processing_Instruction_node:
            case NodeType.CDATA_Section_node:
            case NodeType.Text_node:
            case NodeType.Element_node:
                app.put(n.getTextContent());
                break;
            default:
                break;
            }
            xn = xn.next_;
        }
        while (xn !is null);

        return app.idup;
    }

	/// Take tree apart.  For work of navigating entire tree, might as
	/// delete as well.  Used parts of tree should be removed before calling this.
	override void explode()
	{
		if (attributes_ !is null)
		{
			attributes_.explode();
		}
		auto ch = getFirstChild();
		while(ch !is null)
		{
			auto exploder = ch;
			ch = ch.getNextSibling();
			removeChild(exploder);
			exploder.explode();
		}
		ownerDoc_ = null;
		assert(children_.empty());
		super.explode();
	}

	/// Set the ownerDoc_ member of entire subtree.
    void setDocument(Document d)
    {
        if (ownerDoc_ == d)
            return;

        ownerDoc_ = d;
        ChildNode ch = children_.firstChild_;
        while (ch !is null)
        {
            Element e = cast(Element) ch;
            if (e !is null)
            {
                e.setDocument(d);
            }
            ch = ch.next_;
        }
    }

	/// This is none-DOM, put in because std.xml had it
    @property  XmlString text() const
    {
        return getTextContent();
    }
    /// refChild to insert before must already be a child of this element.
    override Node insertBefore(Node newChild, Node refChild)
    {
        ChildNode xref = (refChild !is null) ? cast(ChildNode) refChild : null;
        if (xref !is null && (xref.parent_ != this))
            throw new DOMFail("insertBefore: not a child of this");

        ChildNode xn = cast(ChildNode) newChild;
        if (xn is null)
        {
            DocumentFragment df = cast(DocumentFragment) newChild;
            if (df is null)
                throw new DOMFail("insertBefore: node is not a ChildNode or DocumentFragment");
            Node join = df.getFirstChild();
            if (join is null)
                throw new DOMFail("insertBefore: Empty DocumentFragment");
            Node jend = df.getLastChild();

            ChildNode nbeg = cast(ChildNode)join;
            ChildNode nend = cast(ChildNode)jend;
            if (xref !is null)
            {
                ChildNode.setParent(nbeg,this);
                children_.insertChainBefore(nbeg, nend, xref);
            }
            else
            {
                ChildNode.setParent(nbeg,this);
                children_.chainAppend(nbeg, nend);
            }
            df.clear();
            return newChild;
        }
        else
        {
            if ( xn.parent_ !is null)
                throw new DOMFail("insertBefore: child already has parent");
            if (xref !is null)
            {
                children_.linkBefore(xn, xref);
            }
            else
            {
                children_.linkAppend(xn);
            }
            xn.setParentNode(this);
            return newChild;
        }
    }

    /// Swap out existing child oldChild, with unparented newChild
    override Node replaceChild(Node newChild, Node oldChild)
    {
        ChildNode xnew = cast(ChildNode)newChild;
        ChildNode xold = cast(ChildNode)oldChild;

        if (xold is null || xnew is null)
            throw new DOMFail("replaceChild: null child node");

        if (xnew.parent_ !is null)
            throw new DOMFail("replaceChild: new child already has parent");

        isChildFail(xold);

        ChildNode prior = xold.prev_;
        if (prior !is null)
        {
            prior.next_ = xnew;
        }
        xnew.prev_ = prior;
        ChildNode post = xold.next_;
        if (post !is null)
        {
            post.prev_ = xnew;
        }
        xnew.next_ = post;
        return oldChild;
    }
    /// Throws exception if not a child of this
    override Node  removeChild(Node oldChild)
    {
        ChildNode xold = cast(ChildNode)oldChild;
        if (xold is null)
            throw new DOMFail("null child node for removeChild");
        if (xold.parent_ != this)
            throw new DOMFail("Not a parent of this element");

        children_.removeLink(xold);
        xold.parent_ = null;
        return oldChild;
    }

    /// Relationships can be important
    bool isChild(ChildNode xn)
    {
        return (xn.parent_ == this);
    }

    /// Exception if not my child
    void isChildFail(ChildNode xn)
    {
        if (xn.parent_ != this)
            throw new DOMFail("Not a child node");
    }



    /// Throws exception if child is attached elsewhere

    override Node  appendChild(Node newChild)
    {
        ChildNode xnew = cast(ChildNode) newChild;
        if (xnew is null)
            throw new DOMFail("null child to appendChild");

        children_.linkAppend(xnew);
        xnew.parent_ = this;
        if (ownerDoc_ !is null)
        {
            Element e = cast(Element) xnew;
            if (e !is null)
                e.setDocument(ownerDoc_);
        }
        return newChild;
    }
    void opCatAssign(ChildNode n)
    {
        appendChild(n);
    }
    /// DOM attribute management
    void removeAttribute(XmlString name)
    {
        if (attributes_ is null)
            return;
        Node n = attributes_.removeNamedItem(name);
    }

    /// DOM attribute management
    Attr removeAttributeNode(Attr old)
    {
        if (attributes_ is null)
            return null;
        Node n = attributes_.removeNamedItem(old.getName());
        return ( n is null ) ? null : cast(Attr) n;
    }

    /// DOM attribute management. NS version not working yet
    void removeAttributeNS(XmlString uri, XmlString local)
    {
        if (attributes_ is null)
            return;
        attributes_.removeNamedItemNS(uri,local);
    }

    /// DOM attribute management
    Attr setAttributeNode(Attr sn)
    {
        if (attributes_ is null)
            attributes_ = new NamedNodeMap();
        Node n = attributes_.setNamedItem(sn);
        return ( n is null ) ? null : cast(Attr) n;
    }
    /// DOM attribute management
    void setAttribute(XmlString name, XmlString value)
    {
        Attr na = new Attr(name);
        na.setValue(value);
        setAttributeNode(na);
    }
    /// DOM attribute management. NS version not working yet
    void setAttributeNS(XmlString nsURI, XmlString qualName, XmlString value)
    {
        if (attributes_ is null)
            attributes_ = new  NamedNodeMap();
        Node n = attributes_.getNamedItemNS(nsURI, qualName);
        if (n is null)
        {
            Attr nat = new  AttrNS(nsURI, qualName);
            nat.setValue(value);
            nat.setOwner(this);
        }
        else
        {
            Attr nat = cast(Attr)n;
            nat.setValue(value);
        }
    }
    override Node getFirstChild()
    {
        return children_.firstChild_;
    }
    override Node getLastChild()
    {
        return children_.lastChild_;
    }



};

/// Seems to work ok
class AttrNS :  Attr
{
protected:
    XmlString uriNS_;
    XmlString localName_;




public:
    /// construct
    this(XmlString name)
    {
        setIdentity(null, name);
    }
    /// constructed with its associated namespace
    this(XmlString nsURI, XmlString name)
    {
        setIdentity(nsURI, name);
    }
    /// return the identifying namespace URI
    override XmlString getNamespaceURI()
    {
        return uriNS_;
    }
    /// The bit after the prefix
    override XmlString getLocalName()
    {
        return localName_;
    }
    /// return the prefix
    override XmlString getPrefix()
    {
        auto poffset = id_.length - localName_.length;
        return  (poffset > 0) ? id_[0..poffset-1] : "";
    }
    void setURI(XmlString nsURI)
    {
        uriNS_ = nsURI;
    }
    void setIdentity(XmlString nsURI, XmlString name)
    {
        id_ = name;
        uriNS_ = nsURI;
        auto pos = std.string.indexOf(id_,':');
        localName_ = (pos >= 0) ? id_[pos+1..$] : id_;
    }

};

/// DOM attribute class with name and value
class Attr : Node
{
protected:
    XmlString value_;
    Element   owner_; // back links make GC harder
    //uint	  flags_;

    enum
    {
        isSpecified = 1,
    };
public:
    this()
    {
    }

    /// Construct
    this(XmlString name)
    {
        super();
        id_ = name;
    }
    /// Construct
    this(XmlString name, XmlString value)
    {
        super();
        id_ = name;
        value_ = value;
    }

    /// Property
    override const NodeType getNodeType()
    {
        return NodeType.Attribute_node;
    }
    /// attribute name
    override XmlString getNodeName()
    {
        return id_;
    }
    /// attribute value
    override XmlString getNodeValue()
    {
        return value_;
    }
    /* forgot what this is for
    bool getSpecified() { return (flags_ & isSpecified) != 0; }*/

    /// Property
    void setOwner(Element e)
    {
        owner_ = e;
    }

	override void explode()
	{
		owner_ = null;
		super.explode();
	}

    /// Property
    final Element getOwnerElement()
    {
        return owner_;
    }
    /// Property
    final XmlString getValue()
    {
        return value_;
    }
    /// Property
    final void setValue(XmlString val)
    {
        value_ = val;
    }
    /// Property
    final XmlString getName()
    {
        return id_;
    }
}

/// Abstract class for all Text related Nodes, Text, CDATA, Comment
abstract class CharacterData :  ChildNode
{
public:

    /// construct with data
    this(XmlString data)
    {
        super(data);
    }

    /// add data
    void appendData(XmlString s)
    {
        id_ ~= s;
    }
    /// delete selected part of data
    void deleteData(int offset, int count)
    {
        id_ = concats(id_[0..offset],id_[offset+count..$]);
    }
    /// return  data
    XmlString getData()
    {
        return id_;
    }
    /// set  data
    void  setData(XmlString s)
    {
        id_ = s;
    }
    /// property of content
    @property final size_t length()
    {
        return id_.length;
    }
    /// sneak in data
    void insertData(int offset, XmlString s)
    {
        id_ = concats(id_[0..offset],s,id_[offset..$]);
    }
    /// stomp on data
    void replaceData(int offset, int count, XmlString s)
    {
        id_ = concats(id_[0..offset], s, id_[offset+count..$]);
    }
    /// Has text, so get it
    override XmlString getTextContent()
    {
        return id_;
    }
	/// Takes text, so set it
	override void setTextContent(XmlString txt)
	{
		id_ = txt;
	}

};

/** Text child of XML elements */
class Text :  CharacterData
{
public:
    this(XmlString s)
    {
        super(s);
    }

    override const NodeType getNodeType()
    {
        return NodeType.Text_node;
    }

    /// Split to put things in between
    Text splitText(int offset)
    {
        auto d2 = id_[offset .. $];

        id_ = id_[ 0.. offset];

        Text t = new Text(id_);
        //t.setDocument(ownerDoc_);
        Node p = getParentNode();
        if (p)
        {
            Element pe = cast(Element)p;
            if (pe !is null)
            {
                Node nx = p.getNextSibling();
                if (nx !is null)
                    pe.insertBefore(t, nx);
                else
                    pe.appendChild(t);
                t.setParentNode(p);
            }
        }
        return t;
    }
    /// D object property
    override  XmlString toXmlString() const
    {
        return id_;
    }

}

/// DOM item
class CDATASection :  Text
{
public:
    this(XmlString data)
    {
        super(data);
    }

    override  NodeType getNodeType() const
    {
        return NodeType.CDATA_Section_node;
    }

    override  XmlString toXmlString() const
    {
        return XMLOutput!T.makeXmlCDATA(id_);
    }
};


/// DOM item
class Comment :  CharacterData
{
public:
    this(XmlString data)
    {
        super(data);
    }

    override  NodeType getNodeType() const
    {
        return NodeType.Comment_node;
    }

    override  XmlString toXmlString() const
    {
        return XMLOutput!T.makeXmlComment(id_);
    }
};

class IdNode :  Node
{
private:
    XmlString	publicId_;
	XmlString	systemId_;

public:

	this(XmlString name)
	{
		id_ = name;
	}
    override XmlString getNodeName()
    {
        return id_;
    }

    XmlString getPublicId()
    {
        return publicId_;
    }
    XmlString getSystemId()
    {
        return systemId_;
    }

	void setSource(XmlString pubId, XmlString sysId)
	{
		publicId_ = pubId;
		systemId_ = sysId;
	}

    XmlString externalSource() const
    {
        Buffer!T result;

		result.reserve(publicId_.length + systemId_.length+ 6);

        void addqt(XmlString n, XmlString v)
        {
            result.put(n);
            result.put(" \'");
            result.put(v);
            result.put('\'');
        }

        if (publicId_.length > 0)
            addqt("PUBLIC",publicId_);
        if (systemId_.length > 0)
		{
			if (publicId_.length == 0)
			{
				addqt("SYSTEM" ,systemId_);
			}
			else {
				addqt([] ,systemId_);
			}
		}
        return result.length > 0 ? result.idup : null;
    }
}



/// DOM node type for entity, a supplement to xml.linkdom, becase EntityData is defined elsewhere.
class Entity : IdNode
{
public:
	XmlString	 value_;
	XmlString	 encoding_;
	XmlString	 version_;
	bool		 isNData_;

    this(XmlString name, XmlString value, bool isNData = false)
    {
		super(name);
		value_ = value;
		isNData_ = isNData;
    }

    override XmlString getNodeValue()
    {
        return !isNData_ ? value_ : null;
    }

    XmlString getNotationName()
    {
        return isNData_ ? value_ : null;
    }
    XmlString getXmlEncoding()
    {
        return encoding_;
    }
    XmlString getInputEncoding()
    {
        return encoding_;
    }
    XmlString getXmlVersion()
    {
        return version_;
    }

    override const NodeType getNodeType()
    {
        return NodeType.Entity_node;
    }
}



class Notation : IdNode
{
	this(XmlString id)
	{
		super(id);
	}

    override 	NodeType getNodeType () const
    {
        return NodeType.Notation_node;
    }

    override    XmlString toXmlString() const
    {
        return concats("<!NOTATION ",id_,' ', externalSource(),">");
    }
}

alias XMLOutput!T.XmlPrinter	PrintDom;

void printDocType(DocumentType dtd, PrintDom tp)
{

    NamedNodeMap nmap = dtd.getNotations();
    if (nmap.getLength > 0)
    {
        auto putOut = tp.options.putDg;
        Buffer!T output;
        output.put("<!DOCTYPE ");
        output.put(dtd.getNodeName());
        output.put(" [");
        immutable putline = tp.options.noWhiteSpace;//crazy canonical compatible
        if (putline)
            output.put('\n');
        putOut(output.data);

        foreach(n ; nmap)
        {
            output.length = 0;
            auto note = cast(Notation) n;
            output.put(n.toXmlString());
            if (putline)
                output.put('\n');
            putOut(output.data);
        }
        output.length = 0;
        output.put("]>");
        if (putline)
            output.put('\n');
        putOut(output.data);
    }
}

void printLinked(Node n, PrintDom tp)
{
    while(n !is null)
    {
        NodeType nt = n.getNodeType();
        switch(nt)
        {

        case NodeType.Element_node:
            printElement(cast(Element)n, tp);
            break;
        case NodeType.Comment_node:
            if (!tp.noComments)
                tp.putIndent(n.toXmlString());
			break;
        case NodeType.CDATA_Section_node:
            tp.putIndent(n.toXmlString());
            break;
        case NodeType.Processing_Instruction_node:
			tp.putIndent(n.toXmlString());
			break;
        case NodeType.Document_type_node:
            // only output if have notations;
            printDocType(cast(DocumentType) n, tp);
            break;
        default:
            auto txt = XMLOutput!T.encodeStdEntity(n.toXmlString(), tp.options.charEntities);
            tp.putIndent(txt);
            break;
        }
        n = n.getNextSibling();
    }
}

void printDocument(Document d, StringPutDg putOut, uint indent)
{
    auto  opt = XMLOutput!T.XmlPrintOptions(putOut);
    DOMConfiguration config = d.getDomConfig();
    Variant v = config.getParameter("canonical-form");
    bool canon = v.get!(bool);
    opt.xversion = to!double(d.getXmlVersion());


    opt.indentStep = indent;

    if (canon)
    {
        opt.emptyTags = false;
        opt.noComments = true;
        opt.noWhiteSpace = true;
    }


    auto tp = PrintDom(opt,indent);
    if (!canon || (opt.xversion > 1.0))
    {
        AttributeMap!T attributes;
        attributes.push("version", d.getXmlVersion());
        if (!canon)
        {
            attributes.push("standalone", d.getXmlStandalone() ? "yes" : "no");
            attributes.push("encoding", d.getXmlEncoding()); // this may not be valid, since its utf-8 string right here.
			attributes.sort();
        }
        //
        XMLOutput!T.printXmlDeclaration(attributes, putOut);
    }
    Node n = d.getRootElement();
    if (n !is null)
        n = n.getFirstChild();
    if (n !is null)
    {
        printLinked(n, tp);
    }
}

void printElement(Element e, PrintDom tp)
{
    bool hasChildren = e.hasChildNodes();
    bool hasAttributes = e.hasAttributes();

    auto putOut = tp.options.putDg;

    auto tag = e.getTagName();
    AttributeMap!T smap;
    if (hasAttributes)
        smap = toAttributeMap(e);

    if (!hasChildren)
    {
        tp.putStartTag(tag, smap, true);
        return;
    }

    Node firstChild = e.getFirstChild();

    if ((firstChild.getNextSibling() is null) && (firstChild.getNodeType() == NodeType.Text_node))
    {
        tp.putTextElement(tag, smap, firstChild.getNodeValue());
        return;
    }

    tp.putStartTag(tag,smap,false);
    auto tp2 = PrintDom(tp);
    printLinked(firstChild, tp2);
    tp.putEndTag(tag);
}


/** Keeps track of active namespace definitions by holding the AttrNS by prefix, or null for default.
	Each time a new definition is encountered a new NameSpaceSet will be stacked.
*/
class  NameSpaceSet
{
version(GC_STATS)
{
	mixin GC_statistics;
	static this()
	{
		setStatsId(typeid(typeof(this)).toString());
	}
}

	alias AttrNS[XmlString] AttrNSMap;

    AttrNSMap		nsdefs_;	 // namespaces defined by <id> or null for default

    /// construct
    this()
    {
		version(GC_STATS)
			gcStatsSum.inc();
    }
    ~this()
    {
		version(GC_STATS)
			gcStatsSum.dec();
    }
	void explode()
	{
		if (nsdefs_ !is null)
		{
			foreach(k ; nsdefs_.byKey)
			{
				nsdefs_.remove(k);
			}
			nsdefs_ = null;
		}
	}

    /// return attribute holding URI for prefix
    AttrNS getAttrNS(XmlString nsprefix)
    {
        auto pdef = nsprefix in nsdefs_;
        return (pdef is null) ? null : *pdef;
    }

}

/// Return AttributeMap (whatever it is), from DOM element
AttributeMap!T toAttributeMap(Element e)
{
    AttributeMap!T result;
    NamedNodeMap atmap = e.getAttributes();

    if (atmap !is null)
    {
        for(uintptr_t i = 0; i < atmap.getLength; i++)
        {
            Attr atnode = cast(Attr)atmap.item(i);
			result.push(atnode.getName(),atnode.getValue());
        }
    }
    return result;
}

	intptr_t splitNameSpace(XmlString name, out XmlString nmSpace, out XmlString local)
	{
		intptr_t sepct = 0;

		auto npos = std.string.indexOf(name, ':');

		if (npos >= 0)
		{
			sepct++;
			nmSpace = name[0 .. npos];
			local = name[npos+1 .. $];
			if (local.length > 0)
			{
				auto temp = local;
				npos = std.string.indexOf(temp,':');
				if (npos >= 0)
				{
					sepct++;  // 2 is already too many
					//temp = temp[npos+1 .. $];
					//npos = indexOf(temp,':');
				}
			}
		}
		else
		{
			local = name;
		}
		return sepct;
	}

	struct ChildElementRange
	{
	private:
		Node		node_;
		Element		e_;

		void nextElement()
		{
			while(node_ !is null)
			{
				e_ = cast(Element) node_;
				node_ = node_.getNextSibling();
				if (e_ !is null)
					return;
			}
			e_ = null;
		}
	public:
		this(Element parent)
		{
			node_ = parent.getFirstChild();
			nextElement();
		}

		@property bool empty()
		{
			return e_ is null;
		}

		@property Element front()
		{
			return e_;
		}

		void popFront()
		{
			nextElement();
		}
	}
	struct DOMVisitor
	{

		private
		{
			Element		parent_;	// parent element
			Node		node_;		// if equals parent, then start or end of element
			int			depth_;		// element depth of parent
			bool		isElement_; // true if node is element
			NodeType	ntype_;
		}

		/// The element whose children are being visited
		@property Element element()
		{
			return parent_;
		}

		private void checkStartElement()
		{
			ntype_ = node_.getNodeType();
			if (ntype_ == NodeType.Element_node)
			{
				depth_++;
				parent_ = cast(Element) node_;
				isElement_ = true;
			}
		}

		private void doEndElement()
		{
			if (depth_ == 0)
			{
				node_ = null;
			}
			else
			{
				depth_--;
				ntype_ = NodeType.Element_node;
				node_ = parent_;
				isElement_ = false;
			}

		}

		/// Current node is an element
		@property bool isElement()
		{
			return isElement_;
		}

		/// NodeType of current node
		@property NodeType nodeType()
		{
			return ntype_;
		}

		/** Indicate travel back up to next sibling of this element,
		without traversing any more of its subtree
		*/
		void doneElement()
		{
			doEndElement();
		}

		/** Set the current Element and its depth.
		Depth zero is the depth at which exit will happen for the element.
		If this is the parent element of all the elements to scan, then 0.
		If this was the first of many siblings, then 1 so that exit depth is 0 at parent.
		*/

		void startElement(Element e, int elemDepth = 0)
		{
			if (elemDepth < 0)
				elemDepth = 0;
			parent_ = e;
			node_ = e;
			depth_ = elemDepth;
			isElement_ = true;
			ntype_ = NodeType.Element_node;
		}


		/// go to the next node, try children of current element first (depth first)
		bool nextNode()
		{
			if (ntype_ == NodeType.Element_node)
			{
				if (isElement_)
				{
					isElement_ = false;
					node_ = parent_.getFirstChild();
					if (node_ is null)
					{
						// end of element
						doEndElement();
					}
					else
						checkStartElement();
				}
				else   // have done end element
				{
					Node next = node_.getNextSibling();
					if (next !is null)
					{
						node_ = next;
						checkStartElement();
					}
					else
					{
						if (depth_ == 0)
							return false;
						depth_--;
						next = node_.getParentNode();
						if (next !is null)
						{
							parent_ = cast(Element) next;
							next = next.getNextSibling();
							if (next !is null)
							{
								node_ = next;
								checkStartElement();
							}
							else
							{
								doEndElement();
							}
						}
						else
							return false;
					}
				}
			}
			else
			{
				Node next2 = node_.getNextSibling();
				if (next2 is null)
				{
					parent_ = cast(Element) node_.getParentNode();
					doEndElement();
				}
				else
				{
					node_ = next2;
					checkStartElement();
				}
			}
			return (node_ !is null);
		}
	}
}//End template XMLDom

