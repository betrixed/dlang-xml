/**
A very abbreviated Xml tree, with array of Item instead of links.
DOM features:  NodeType in base class Item.

Authors: Michael Rynn
*/

module xml.xmlArrayDom;

import std.stdio;
import xml.util.buffer;
import xml.txml;
import xml.input;
import xml.dtd;

import std.string, std.conv, std.exception;
import std.variant;


//debug = VERBOSE;
debug(VERBOSE)
{
	import std.stdio;
}

/// Dom is like std.xml
/// Elements, Attributes, nodes, have no parent or owner member.

import xml.xmlOutput;
import xml.parser;
import xml.attribute;

template XMLArrayDom(T)  {

    alias immutable(T)[] XmlString;
    alias AttributeMap!T    Attributes;
    alias XmlEvent!T        XmlReturn;

	alias xout = xml.xmlOutput.XMLOutput!T;

	alias xout.makeXmlComment makeXmlComment;
	alias xout.makeXmlCDATA makeXmlCDATA;
	alias xout.makeXmlProcessingInstruction makeXmlProcessingInstruction;
	alias xout.printXmlDeclaration printXmlDeclaration;
	alias xout.XmlPrintOptions XmlPrintOptions;
	alias xout.XmlPrinter XmlPrinter;
	alias xout.StringPutDg		StringPutDg;

	alias Buffer!Item		ItemList;


	abstract class Item
	{
		void explode()
		{

		}

		abstract XmlString toXml() const;

		/// This item as text
		override string toString() const
		{
			return to!string(toXml());
		}
		///  Item tree as text array
		XmlString[] pretty(uint indent)
		{
			XmlString s = strip(toXml());
			return s.length == 0 ? [] : [ s ];
		}

		final NodeType nodeType()   const @property
		{
			return nodeType_;
		}
	private:
		NodeType	nodeType_;
	}


/// For Text, CDATA, and Comment
class Text :  Item
{
    ///
    XmlString content;

    this(immutable(T)[] c)
    {
        content = c;
        nodeType_ = NodeType.Text_node;
    }

    XmlString getContent()
    {
        return content;
    }

    override  XmlString toXml() const
    {
        return content;
    }
}

/// Comments
class Comment :  Text
{
    this(XmlString s)
    {
        super(s);
        nodeType_ = NodeType.Comment_node;
    }
    override XmlString toXml() const
    {
        return makeXmlComment(content);
    }
};

/// CDATA for text with markup
class CData :  Text
{
    this(XmlString s)
    {
        super(s);
        nodeType_ = NodeType.CDATA_Section_node;
    }
    override  XmlString toXml() const
    {
        return makeXmlCDATA(content);
    }
}


/**
ProcessingInstruction has target name, and data content
*/
class ProcessingInstruction : Text
{
    XmlString target;

    this(XmlString target, XmlString data)
    {
        super(data);
        this.target = target;
        nodeType_ = NodeType.Processing_Instruction_node;
    }
    override  XmlString toXml() const
    {
        return makeXmlProcessingInstruction(target,content);
    }
}



/**
Simplified Element, name in content field,  with all children in array, attributes in a block
*/
class Element :  Item
{
    Attributes   			attr;
    ItemList				children;
    XmlString				tag;

    this(XmlString id, Attributes amap)
    {
        this(id);
        attr = amap;
    }
    this(XmlString id, XmlString content)
    {
        this(id);
        children.put(new Text(content));

    }

    bool hasAttributes()
    {
        return (attr.length > 0);
    }
    ref auto getAttributes()
    {
        return attr;
    }
    alias getAttributes attributes;

    this(XmlString id)
    {
        tag = id;
        nodeType_ = NodeType.Element_node;
    }

    this()
    {
        nodeType_ = NodeType.Element_node;
        tag = (immutable(T)[]).init;
    }

	override void explode()
	{
		foreach(item ; children)
		{
			item.explode();
		}
		children.reset();
		super.explode();
	}

	int opApply(int delegate(Item item) dg)
	{
		foreach(item ; children)
		{
            int result = dg(item);
            if (result)
                return result;
		}
		return 0;
	}

    auto childElements()
    {
		return children[];
    }

    void setChildren(ItemList chList)
    {
        children = chList;
    }

    auto getChildren()
    {
		return children[];
    }

    void removeAttribute(XmlString key)
    {
		//attr.remove(key);
    }
    void setAttribute(XmlString name, XmlString value)
    {
		//attr[name] = value;
    }

    final bool empty()
    {
        return children.length == 0;
    }

    void appendChild(Item n)
    {
		children.put(n);
    }
    alias appendChild opCatAssign;

	void addText(XmlString s)
	{
		appendChild(new Text(s));
	}

	void addCDATA(XmlString s)
	{
		appendChild(new CData(s));
	}

	void addComment(XmlString s)
	{
		appendChild(new Comment(s));
	}

    /**
	* Returns the decoded interior of an element.
	*
	* The element is assumed to containt text <i>only</i>. So, for
	* example, given XML such as "&lt;title&gt;Good &amp;amp;
	* Bad&lt;/title&gt;", will return "Good &amp; Bad".
	*
	* Params:
	*      mode = (optional) Mode to use for decoding. (Defaults to LOOSE).
	*
	* Throws: DecodeException if decode fails
	*/
    @property  XmlString text() const
    {

        Buffer!T	app;
        foreach(item; children.peek)
        {
			auto nt = item.nodeType;
			switch(nt)
			{
				case NodeType.Text_node:
					Text t = cast(Text) cast(void*) item;
					if (t !is null)
						app.put(t.content);
					break;
				case NodeType.Element_node:
					Element e = cast(Element) cast(void*) item;
					if (e !is null)
						app.put(e.text);
					break;
				default:
					break;

			}

        }
        return app.idup;
    }


    /**
	* Returns an indented string representation of this item
	*
	* Params:
	*      indent = (optional) number of spaces by which to indent this
	*          element. Defaults to 2.
	*/
    override XmlString[] pretty(uint indent)
    {
        Buffer!XmlString app;

        void addstr(const(T)[] s)
        {
            app.put(s.idup);
        }
        auto opt = XmlPrintOptions(&addstr);

        auto tp = XmlPrinter(opt, indent);

        printElement(cast(Element)this, tp);

        return app.take;
    }

    override XmlString toXml() const
    {
        Buffer!T result;

        void addstr(const(T)[] s)
        {
            result.put(s);
        }
        auto opt = XmlPrintOptions(&addstr);
        auto tp = XmlPrinter(opt);
        printElement(cast(Element)this, tp);
        return result.idup();
    }
}


class XmlDec : Item
{
private:
    Attributes attr;
public:
    auto ref getAttributes()
    {
        return attr;
    }

    void removeAttribute(XmlString key)
    {
        attr.removeName(key);
    }

    void setAttribute(XmlString name, XmlString value)
    {
        attr[name] = value;
    }
}

/// Document is an Element with a member for the document Element
class Document : Element
{
private:
    Element			docElement_;
public:

    this(Element e = null)
    {
        nodeType_ = NodeType.Document_node;
        if (e !is null)
        {
			children.put(e);
            docElement_ = e;
        }
    }

	Element  docElement() @property
	{
		return docElement_;
	}
    void setXmlVersion(XmlString v)
    {
        attr["version"] = v;
    }

    void setStandalone(bool value)
    {
        XmlString s = value ? "yes" : "no";
        attr["standalone"] = s;
    }

    void setEncoding(XmlString enc)
    {
        attr["encoding"] = enc;
    }

	override void explode()
	{
		docElement_ = null; // avoid dangler
		super.explode();
	}

    override void appendChild(Item e)
    {
        Element elem = cast(Element) e;
        if (elem !is null)
        {
            if (docElement_ is null)
            {
                docElement_ = elem;
            }
            else
            {
                docElement_.appendChild(elem);
                return;
            }
        }
		children.put(e);

    }
    /**
	* Returns an indented string representation of this item
	*
	* Params:
	*      indent = (optional) number of spaces by which to indent this
	*          element
	*/
    override XmlString[] pretty(uint indent = 2)
    {
        Buffer!XmlString app;

        void addstr(const(T)[] s)
        {
            app.put(s.idup);
        }
        printOut(&addstr, indent);
        return app.take;
    }

    void printOut(StringPutDg dg, uint indent = 2)
    {
        auto opt = XmlPrintOptions(dg);
        auto tp = XmlPrinter(opt, indent);
        size_t alen = attr.length;
        if (alen > 0)
        {
            printXmlDeclaration((cast(Document) this).getAttributes(), dg);
        }
		printItems(children.peek, tp);

    }

};
/// print element children
void printItems(const Item[] items, ref XmlPrinter tp)
{
    if (items.length == 0)
        return;

    foreach(item ; items)
    {
        Element child = cast(Element) item;
        if (child is null)
        {
            tp.putIndent(item.toXml());
        }
        else
        {
            printElement(child, tp);
        }
    }
}


/// Output with core print
void printElement(Element e, ref XmlPrinter tp)
{
    auto ilen = e.children.length;
    auto atlen = e.attr.length;

    if (ilen==0 && atlen==0)
    {
        tp.putEmptyTag(e.tag);
        return;
    }
    if (e.children.length == 0)
    {
        tp.putStartTag(e.tag, e.attributes(),true);
        return;
    }

    if (e.children.length == 1)
    {
        Text t = cast(Text)(e.children[0]);
        if (t !is null)
        {
            tp.putTextElement(e.tag, e.attributes(), t.toXml());
            return;
        }
    }

    tp.putStartTag(e.tag, e.attr,false);

    auto tp2 = XmlPrinter(tp);

	printItems(e.children.peek, tp2);

    tp.putEndTag(e.tag);
}


/// Element from TAG_START or TAG_EMPTY
Element createElement(const XmlReturn ret)
{
    Element e = new Element(ret.data);
	e.attr = ret.attributes;
    return e;
}

/// collector callback class
class ArrayDomBuilder : IBuildDom!T
{
    Buffer!Element		elemStack_;
    Element			    root_;
    Element				parent_;
	XmlParser!T			parser_;
	DocTypeData!T		doctype_;

    this()
    {
		parser_ = new XmlParser!T();
    }
    @property {
        Document document() {
            return cast(Document) root_;
        }
        void document(Document d) {
            root_ = d;
            parent_ = d;
        }
    }

	Element root() @property
	{
		return root_;
	}

    void startDoctype(const XmlEvent!T evt)
	{
		doctype_ = cast( DocTypeData!T ) evt.obj; // get DocTypeData from parser
	}
    void endDoctype(const XmlEvent!T evt)
	{
	}
    void notation(const XmlEvent!T evt)
	{
	}
    void startTag(const XmlEvent!T ret)
    {
        auto e = createElement(ret);
		if (parent_ is null)
		{
			root_ = e;
			parent_ = e;
		}
		else {
			elemStack_.put(parent_);
			parent_.appendChild(e);
			parent_ = e;
		}
    }
    void soloTag(const XmlEvent!T ret)
    {
        parent_ ~= createElement(ret);
    }

    void endTag(const XmlEvent!T ret)
    {
		if (elemStack_.length > 0)
		{
			parent_ = elemStack_.movePopBack();
		}
        else {
			parent_ = null;
		}
    }
    void text(const XmlEvent!T ret)
    {
        parent_.addText(ret.data);
    }
    void cdata(const XmlEvent!T ret)
    {
        parent_.addCDATA(ret.data);
    }
    void comment(const XmlEvent!T ret)
    {
        parent_.addComment(ret.data);
    }
    void instruction(const XmlEvent!T ret)
    {
		auto p = ret.attributes[0];
		parent_.appendChild(new ProcessingInstruction(p.name, p.value));
    }
    void declaration(const XmlEvent!T ret)
    {
		root_.attr = ret.attributes;
    }
	void explode()
	{
		destroy(this);
	}

	@property void normalizeAttributes(bool value)
	{
	    parser_.setParameter(xmlAttributeNormalize,Variant(value));
	}
	void setSource(S)(const(S)[] src)
	{
		parser_.fillSource(new SliceBuffer!S(src));
	}

	void setFile(string filename)
	{
		parser_.fillSource = new XmlFileReader(filename);
	}

	void setSourceSlice(immutable(T)[] data)
	{
		parser_.initSource(data);
	}

    bool parserEvent(XmlEvent!T evt) {
        switch(evt.eventId) {
        case SAX.TAG_START:
            startTag(evt);
            break;
        case SAX.TAG_SINGLE:
            soloTag(evt);
            break;
        case SAX.TAG_END:
            endTag(evt);
            break;
        case SAX.TEXT:
            text(evt);
            break;
        default:
            break;

        }
        return true;
    }
	void parseDocument()
	{
	    if (root_ is null)
        {
            document = new Document();
        }
        parser_.setEventDg(&parserEvent);

		parser_.parseAll();
	}

}


void parseArrayDom(S)(Document doc, immutable(S)[] sxml)
{
    auto builder = new ArrayDomBuilder();
    scope(exit)
        builder.explode();
    builder.document = doc;
    builder.setSource!S(sxml);
    builder.parseDocument();
}

} // XMLArrayDom


