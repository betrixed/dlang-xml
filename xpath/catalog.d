/**
 * NodeSet and NodeCatalog are complementary classes.
 * They nest each other recursively to provide a useful index for XPath
 * searches, and also present the results of an XPath lookup.
 *
 * Authors: Michael Rynn, michaelrynn@optusnet.com.au
 * Date: November 25, 2009
 *
 **/

/**
    The catalog holds element references, and must use a dom definition of Element
*/
module xpath.catalog;

import xml.sxml;
import std.stdint;
import std.conv;
import std.algorithm;

class NodeSetException : Exception {
    this(string msg) { super(msg); }
}
/**
 * NodeSet is a list of NodeCatalog.
 * Access is range and cast checked where possible.
 * Indexable and exception checked properties of element and attribute.
 **/

class NodeSet {
	NodeCatalog[] nodes;

	static void NodeSetIndexException()
	{
		throw new NodeSetException("index exceeds NodeSet range");
	}

	static void NodeSetCastException()
	{
		throw new NodeSetException("Item cast to null");
	}
	NodeCatalog opIndex(uint ix)
	{
		if (ix >= nodes.length)
			NodeSetIndexException();
		return nodes[ix];
	}

	uintptr_t length()
	{
		return nodes.length;
	}

	Element element(uint ix)
	{
		if (ix >= nodes.length)
			NodeSetIndexException();

		return nodes[ix].element;
	}
	string attribute(uint ix)
	{
		if (ix >= nodes.length)
			NodeSetIndexException();
		Attribute atb = nodes[ix].attribute;
		if (atb is null)
			NodeSetCastException();
		return atb.getValue();
	}

	string data(uint ix)
	{
		if (ix >= nodes.length)
			NodeSetIndexException();
		return nodes[ix].node.getNodeValue();
	}

	void output(void delegate(string s) dg)
	{
        dg("NodeSet:");
        foreach(n ; nodes)
        {
            n.output(dg);
        }
	}
}

class NodeCatalog
{
public:
	Item	node;

	this(Item xitem)
	{
		this.node = xitem;
	}
	NodeSet getChildSet(string ename)
	{
		return null;
	}

	Attribute attribute()
	{
		return cast(Attribute) node;
	}

	Element element()
	{
		return cast(Element) node;
	}
	void output(void delegate(string s) dg)
	{
        dg(text("NodeCatalog:",node.getNodeValue()));
	}
}

/**
 * A XML document is supplemented by a catalog of each element
 * that indexes child elements based on name.
 * This helps support the XPath lookups by name.
 * Each unique element name is a NodeSet.
 *
 * A NodeCatalog is also created on demand for XPath lookups that return
 * non-element items such as Attribute or Text nodes.
 **/

class ElemCatalog : NodeCatalog {
	ElemCatalog 			    parent;
	NodeSet[string]			children;

	enum {
		TEST_EXITSEARCH = -1,
		TEST_SKIP = 0,
		TEST_INCLUDE = 1,
		TEST_INCLUDE_EXIT = 2
	}
	alias int delegate(string atvalue) AttributeTestDg;
public:
	this(Item xitem)
	{
		super(xitem);
	}
	override NodeSet getChildSet(string ename)
	{
		NodeSet* pns = ename in children;
		return (pns is null) ? null : *pns;
	}

	NodeSet getElementSet(string ename, string atrname, AttributeTestDg test)
	{
		NodeSet result = new NodeSet();
		NodeSet ns  = getChildSet(ename);

		if (ns !is null)
		{
			// test each element, if test is true add to result
			// atrvalue may be null, which can be part of the test.
			foreach(ex ; ns.nodes)
			{
				Element e = cast(Element) ex.node;
				if (e !is null)
					switch(test(e.getAttribute(atrname)))
					{
					case TEST_INCLUDE:
						result.nodes ~= ex;
						break;
					case TEST_SKIP:
						break;
					case TEST_INCLUDE_EXIT:
						result.nodes ~= ex;
						break;
					default:
						return result;
					}
			}
		}
		return result;
	}

	NodeCatalog get(string ename, uint ix)
	{
		NodeSet ns  = getChildSet(ename);

		if (ns !is null)
		{
			if (ns.nodes.length > ix)
				return ns.nodes[ix];
		}
		return null;
	}

    override void output(void delegate(string s) dg)
    {
        dg(text("ElemCatalog:"));
        auto keys = children.keys();
        auto skey = keys.sort!("a<b");
        foreach(k ; skey)
        {
            dg(text(k,":"));
            auto ns = children[k];
            ns.output(dg);
        }
    }
};

ElemCatalog CatalogElement(Element e)
{
	ElemCatalog ec = new ElemCatalog(e);

	NodeSet   ns;
	NodeSet	  all;

	auto nlist = e.getChildElements();
	uintptr_t ix = 0;
	foreach(ch ; nlist)
	{
        ix++;
		string ename = ch.getNodeValue();

		if (ix == 1)
		{
			all = new NodeSet();
			ec.children["*"] = all;
		}

		NodeSet* pns = ename in ec.children;
		if (pns is null)
		{
			ns = new NodeSet();
			ec.children[ename] = ns;
		}
		else
			ns = *pns;

		/// also a '*'
        Element e = cast(Element)ch;
		ElemCatalog chcat = CatalogElement(e);
		chcat.parent = ec;
		ns.nodes ~= chcat;
		all.nodes ~= chcat;

	}
	return ec;
}

ElemCatalog CatalogDocument(Document d)
{
    // Tricky, but supply the element that parents the document element
	return CatalogElement(d.getRootElement());
}

