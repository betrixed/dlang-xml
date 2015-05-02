module xml.parse.arrayt;

import xml.parse.dxml;

import xml.ixml, xml.dom.arrayt;
import alt.buffer;
import std.variant, std.stream;
import xml.parse.input;


/// collector callback class
class ArrayDomBuilder(T) : NullDocHandler!T
{
	alias XMLARRAY!T.createElement createElement;
	alias XMLARRAY!T.Element Element;
	alias XMLARRAY!T.Document Document;
	alias XmlEvent!T	XmlReturn;
	alias XMLARRAY!T.ProcessingInstruction ProcessingInstruction;

    Buffer!Element		elemStack_;
    Element			    root_;
    Element				parent_;
	DXmlParser!T		parser_;

    this()
    {
		parser_ = new DXmlParser!T();
		parser_.docInterface = this;
		parser_.errorInterface = this;
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

    override void startTag(XmlReturn ret)
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
    override void soloTag(XmlReturn ret)
    {
        parent_ ~= createElement(ret);
    }

    override void endTag(XmlReturn ret)
    {
		if (elemStack_.length > 0)
		{
			parent_ = elemStack_.movePopBack();
		}
        else {
			parent_ = null;
		}
    }
    override void text(XmlReturn ret)
    {
        parent_.addText(ret.scratch);
    }
    override void cdata(XmlReturn ret)
    {
        parent_.addCDATA(ret.scratch);
    }
    override void comment(XmlReturn ret)
    {
        parent_.addComment(ret.scratch);
    }
    override void instruction(XmlReturn ret)
    {
		auto p = ret.attr.atIndex(0);
		parent_.appendChild(new ProcessingInstruction(p.id, p.value));
    }
    override void declaration(XmlReturn ret)
    {
		root_.attr = ret.attr;
    }
	void explode()
	{
		this.clear();
	}

	@property void normalizeAttributes(bool value)
	{
	    parser_.setParameter(xmlAttributeNormalize,Variant(value));
	}
	void setSource(S)(const(S)[] src)
	{
		parser_.fillSource(new SliceFill!S(src));
	}

	void setFile(string filename)
	{
        auto s = new BufferedFile(filename);
		parser_.fillSource = new XmlStreamFiller(s);
	}
    //
	void setFileSlice(string filename)
	{
		parser_.sliceFile(filename);
	}

	void setSourceSlice(immutable(T)[] data)
	{
		parser_.initSource(data);
	}

	void parseDocument()
	{
	    if (root_ is null)
        {
            document = new Document();
        }
		parser_.parseAll();
	}

}


void parseArrayDom(T,S)(XMLARRAY!T.Document doc, immutable(S)[] sxml)
{
    auto builder = new ArrayDomBuilder!T();
    scope(exit)
        builder.explode();
    builder.document = doc;
    builder.setSource!S(sxml);
    builder.parseDocument();
}
