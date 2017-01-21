/**
 * ShortXPath.
 *
 * XPath abbreviated form partially implemented.
 *
 * The shortXPath function returns an XPathExpression class.
 * XPathExpression is a parsed executable form of the path string.
 * The XPathExpression class instance can be used multiple times with the
 * xpathNodeSet function.
 *
 * Expressions not supported (yet).
 * //   any path.
 * ..	parent
 * .	context
 * @*	all attributes
 * position()
 * last()
 *
 * Authors: Michael Rynn, michaelrynn@optusnet.com.au
 * Date: November 25, 2009
 *
 **/

module xpath.tiny;


import std.ascii;
import std.stdint;
import std.conv;

import texi.read;
import texi.buffer;

import xpath.parser;
import xpath.catalog;

import xml.sxml;
import xml.xmlChar;

import std.exception;

class XPathException : Exception {
	this(string msg)
	{
		super(msg);
	}
};

alias XPathParse  InText;

		private enum XPathShort {
			XP_EMPTY,
			XP_ROOT,
			XP_SEP,
			XP_ALL,
			XP_ALLPATHS,
			XP_ALL_ATTR,
			XP_QNAME,
			XP_PREDICATE_BEGIN,
			XP_PREDICATE_END,
			XP_INTEGER,
			XP_FUNCTION,
			XP_QT_STRING,
			XP_INDEX,
			XP_REAL,
			XP_ATTR_NAME,
			XP_VCOMP_EQ,
			XP_DOT,
			XP_PARDOT,
			XP_ATTSIGN,
			XP_EXPRESSION,
			XP_SELECT,
			XP_TEXT,
			XP_LAST,
			XP_POSITION,
			XP_UNKNOWN,

		}



		///"=" | "!=" | "<" | "<=" | ">" | ">="
	enum CompOp {
	NO_OP,
	GC_EQ,
	GC_NE,
	GC_LT,
	GC_LE,
	GC_GT,
	GC_GE,

///"eq" | "ne" | "lt" | "le" | "gt" | "ge"

	VC_EQ,
	VC_NE,
	VC_LT,
	VC_LE,
	VC_GT,
	VC_GE,
///"is" | "<<" | ">>"
	NC_IS,
	NC_LL,
	NC_GG,

/// some other ops
	OP_INDEX,
	}
	class CompOpEnum {

		private static CompOp[dchar[]] map;

		static CompOp lookup(dchar[] s)
		{
			CompOp* pval = s in map;
			if (pval is null)
				return CompOp.NO_OP;
			else
				return *pval;
		}

		static this()
		{
			map["="d] = CompOp.GC_EQ;
			map["!="d] = CompOp.GC_NE;
			map["<"d] = CompOp.GC_LT;
			map["<="d] = CompOp.GC_LE;
			map[">"d] = CompOp.GC_GT;
			map[">="d] = CompOp.GC_GE;

			map["eq"d] = CompOp.VC_EQ;
			map["ne"d] = CompOp.VC_NE;
			map["lt"d] = CompOp.VC_LT;
			map["le"d] = CompOp.VC_LE;
			map["gt"d] = CompOp.VC_GT;
			map["ge"d] = CompOp.VC_GE;

			map["is"d] = CompOp.NC_IS;
			map["<<"d] = CompOp.NC_LL;
			map[">>"d] = CompOp.NC_GG;

		}
	}

	private enum XPathFull {
		KW_CHILD,
		KW_DESCENDENT
	}

/// Simple minded union typed data for XPathData variant part
/// This could muck up garbage collection and type metadata.
union  opvar {
	uint	   opIndex;
	int		   opInteger;
	double	   opReal;
	string	   opString;
	XPathExpression	opExpression;
	XPathCompOp		opSelect;
}

struct XPathData {
	XPathShort optype;  // optypes
	opvar	   opdata;

}

class XPathCompOp {
	CompOp	    op;
	XPathData	d1;
	XPathData	d2;
}

struct PredicateContext {
		XPathCompOp	cop;
		Element pe;
		uintptr_t	pos;
		uintptr_t	size;
}

class XPathExpression {
	XPathData[] code;

	void append(XPathData di)
	{
		code ~= di;
	}

	void attrName(string qname)
	{
		uintptr_t slen = code.length;
		code.length = slen+1;
		XPathData* di = &code[slen];
		di.optype = XPathShort.XP_ATTR_NAME;
		di.opdata.opString = qname;
	}

	void childElement(string qname)
	{
		uintptr_t slen = code.length;
		code.length = slen+1;
		XPathData* di = &code[slen];
		di.optype = XPathShort.XP_QNAME;
		di.opdata.opString = qname;
	}

	void elemCondition(ref XPathCompOp pred)
	{
		uintptr_t slen = code.length;
		code.length = slen+1;
		XPathData* di = &code[slen];
		if (pred.op == CompOp.OP_INDEX)
		{
			di.optype = XPathShort.XP_INDEX;
			di.opdata.opIndex = pred.d1.opdata.opIndex;
		}
		else {
			di.optype = XPathShort.XP_SELECT;
			di.opdata.opSelect = pred;
		}
	}

	void noData(XPathShort sfn)
	{
		uintptr_t slen = code.length;
		code.length = slen+1;
		XPathData* di = &code[slen];
		di.optype = sfn;
		di.opdata.opIndex = 0xFFFFFFFF;
	}

}

CompOp parseOp(InText spi)
{
	int spacect = spi.getSpaceCt();
	if (spi.empty)
		return CompOp.NO_OP;
	// try 2 characters
	dchar[] buf;
	CompOp result;

	buf ~= spi.front;
	spi.popFront;
	if (!spi.empty)
	{
		buf ~= spi.front;
		spi.popFront;
		result = CompOpEnum.lookup(buf);
		if (result != CompOp.NO_OP)
			return result;
		spi.pushFront(buf[1]);
		buf.length = 1;
	}
	// maybe only one character
	result = CompOpEnum.lookup(buf);
	if (result != CompOp.NO_OP)
		return result;
	spi.pushFront(buf[0]);
	return CompOp.NO_OP;
}

XPathShort parseXPathShort(InText spi, ref string pdata)
{
	bool isNoArgFunction()
	{
		spi.popFront;
		bool result = (!spi.empty && spi.front == ')');
		if (result)
			spi.popFront;
		return result;
	}
	Buffer!char wbuf;

	if (spi.empty)
		return XPathShort.XP_EMPTY;
	dchar test = spi.front;
	spi.popFront();
	switch(test)
	{
	case '*':
		return XPathShort.XP_ALL;
	case '.':
		if (!spi.empty && spi.front == '.')
		{
			spi.popFront;
			return XPathShort.XP_PARDOT;
		}
		else {
			// maybe its a number?
			if (std.ascii.isDigit(spi.front))
				spi.pushFront('.');
			else
				return XPathShort.XP_DOT;
		}
		break;
	case '/':
		if (!spi.empty && spi.front == '/')
		{
            spi.popFront;
			return XPathShort.XP_ALLPATHS;
		}
		else {
			return XPathShort.XP_SEP;
		}
	case '[':
		return XPathShort.XP_PREDICATE_BEGIN;
	case ']':
		return XPathShort.XP_PREDICATE_END;
	case '@':

		if (spi.getQName(wbuf))
		{
			pdata = wbuf.data.idup;
			return XPathShort.XP_ATTR_NAME;
		}
		else {
			if (spi.front == '*')
			{
				spi.popFront;
				return XPathShort.XP_ALL_ATTR;
			}
			else
			{
				return XPathShort.XP_UNKNOWN;
			}
		}

	case '\'':
	case '\"':
		spi.pushFront(test);
		spi.unquote(wbuf);
		pdata = wbuf.data.idup;
		return XPathShort.XP_QT_STRING;
	default:
		break;
	}

	dchar[]   name_d;

	if (isDigit(test) || (test == '-') || (test == '.'))
	{
		// collect a number?
		spi.pushFront(test);

		NumberClass nc = spi.parseNumber(wbuf);
		if (nc<=NumberClass.NUM_EMPTY)
			return XPathShort.XP_UNKNOWN;
		pdata = wbuf.data.idup;
		return (nc==NumberClass.NUM_INTEGER) ? XPathShort.XP_INTEGER : XPathShort.XP_REAL;

	}
	else if (isNameStartChar11(test))
	{
		spi.pushFront(test);
		spi.getQName(wbuf);
		pdata = wbuf.data.idup;
		if (!spi.empty && spi.front == '(')
		{
			// match a special function name?
			switch(pdata)
			{
			case "text":
				if (isNoArgFunction())
					return XPathShort.XP_TEXT;
				break;
			case "last":
				if (isNoArgFunction())
					return XPathShort.XP_LAST;
				break;
			case "position":
				if (isNoArgFunction())
					return XPathShort.XP_POSITION;
				break;
			default:
				break;
			}
		}
		return XPathShort.XP_QNAME;
	}

	return XPathShort.XP_UNKNOWN;
}



/// Try and get an integer or a name
bool parseData(InText spi, ref XPathData data)
{
	string    test;
	bool expectAttributeName = false;

	for(;;)
	{
		XPathShort token = parseXPathShort(spi, test);
		switch(token)
		{
			case XPathShort.XP_DOT:
				// in this context its the text?
				data.optype = XPathShort.XP_TEXT;
				data.opdata.opInteger = 0;
				return true;
			case XPathShort.XP_ATTR_NAME:
				data.optype = XPathShort.XP_ATTR_NAME;
				data.opdata.opString = test;
				return true;
			case XPathShort.XP_QNAME:
				data.optype = (expectAttributeName?XPathShort.XP_ATTR_NAME:XPathShort.XP_QNAME);
				data.opdata.opString = test;
				return true;

			case XPathShort.XP_PREDICATE_END:
				return false;

			case XPathShort.XP_QT_STRING:
				data.optype = XPathShort.XP_QT_STRING;
				data.opdata.opString = test;
				return true;

			case XPathShort.XP_INTEGER:
				if (expectAttributeName)
					throw new XPathSyntaxError("Expect a name");
				data.optype = XPathShort.XP_INTEGER;
				data.opdata.opInteger = to!int(test);
				return true;

			case XPathShort.XP_REAL:
				if (expectAttributeName)
					throw new XPathSyntaxError("Expect a name");
				data.optype = XPathShort.XP_REAL;
				data.opdata.opReal = to!double(test);
				return true;

			default:
				throw new XPathSyntaxError("bad expression");
		}
	}
}


bool isNumeric(XPathShort val)
{
	switch(val)
	{
	case XPathShort.XP_INTEGER:
	case XPathShort.XP_REAL:
	case XPathShort.XP_LAST:
	case XPathShort.XP_POSITION:
		return true;
	default:
		return false;
	}
}

bool toString(Element e, ref XPathData d, ref string value)
{
	switch(d.optype)
	{
	case XPathShort.XP_QT_STRING:
		value = d.opdata.opString;
		return  true;

	case XPathShort.XP_ATTR_NAME:
		value = e[d.opdata.opString];
		return (value !is null);
	case XPathShort.XP_TEXT:
		value = e.text;
		return (value !is null);
	default:
		return false;
	}
}

bool toNumber(ref PredicateContext ctx, ref XPathData d, ref double value)
{
	string pdata;
	switch(d.optype)
	{
	case XPathShort.XP_REAL:
		value = d.opdata.opReal;
		return true;
	case XPathShort.XP_INTEGER:
		value = d.opdata.opInteger;
		return true;
	case XPathShort.XP_ATTR_NAME:
		pdata = ctx.pe[d.opdata.opString];
		if (pdata is null)
			return false;
		value = to!double(pdata);
		return true;
	case XPathShort.XP_TEXT:
		pdata = ctx.pe.text;
		if (pdata is null)
			return false;
		value = to!double(pdata);
		return true;
	case XPathShort.XP_LAST:
		value = ctx.size-1;
		return true;
	case XPathShort.XP_POSITION:
		value = ctx.pos;
		return true;
	default:
		return false;
	}
}
bool
executeCompOp(CompOp op, ref string s1, ref string s2)
{
	switch(op)
	{
	case CompOp.GC_EQ:
	case CompOp.VC_EQ:
		return (s1 == s2);
	case CompOp.GC_NE:
	case CompOp.VC_NE:
		return (s1 != s2);
	default:
		throw new XPathRunError("bad string compare op");
	}
	assert(0);
}

bool
executeCompOp(CompOp op, double v1, double v2)
{
	switch(op)
	{
	case CompOp.GC_EQ:
	case CompOp.VC_EQ:
		return (v1 == v2);
	case CompOp.GC_NE:
	case CompOp.VC_NE:
		return (v1 != v2);
	case CompOp.GC_LT:
	case CompOp.VC_LT:
		return (v1 < v2);
	case CompOp.GC_LE:
	case CompOp.VC_LE:
		return (v1 <= v2);
	case CompOp.VC_GT:
	case CompOp.GC_GT:
		return (v1 > v2);
	case CompOp.GC_GE:
	case CompOp.VC_GE:
		return (v1 >= v2);
	default:
		throw new XPathRunError("Invalid operator for number compare");
	}
	assert(0);
}

bool evaluatePredicate(ref PredicateContext ctx)
{
	with (ctx)
	{
		if (cop.op == CompOp.NO_OP)
		{
			switch(cop.d1.optype)
			{
			case XPathShort.XP_ATTR_NAME:
				return pe.hasAttribute(cop.d1.opdata.opString);
			default:
				throw new  XPathRunError("unsupported no-op predicate");
			}
		}
		else {
			bool compNumber = isNumeric(cop.d1.optype) || isNumeric(cop.d2.optype);

			double val1, val2;

			if (compNumber)
			{
				if (!toNumber(ctx,cop.d1, val1) || !toNumber(ctx,cop.d2,val2))
				{
					return false; // just not comparable?
				}
				return executeCompOp(cop.op, val1, val2);
			}
			else {
				// string comparison is = or !=
				string s1, s2;

				if (!toString(pe, cop.d1, s1) || !toString(pe, cop.d2, s2))
				{
					return false;
				}
				return executeCompOp(cop.op, s1, s2);
			}
		}
	}
	assert(0);
}

bool parsePredicate(InText spi, ref XPathCompOp bop)
{
	// get an expression of X op Y,  or maybe just X,

	XPathData d1;
	XPathData d2;

	if (parseData(spi, d1))
	{
		CompOp op = parseOp(spi);
		if (op != CompOp.NO_OP)
		{
			if (parseData(spi,d2))
			{
				bop = new XPathCompOp;
				bop.d1 = d1;
				bop.d2 = d2;
				bop.op = op;
				return true;
			}
			else
				return false;
		}
		if (d1.optype == XPathShort.XP_INTEGER)
		{
			bop = new XPathCompOp;
			bop.d1 = d1;
			bop.op = CompOp.OP_INDEX;
			return true;
		}
	}
	return false;
}

NodeSet xpathNodeSet(NodeCatalog cat, string xps)
{
	return xpathNodeSet(cat,shortXPath(xps));
}


NodeSet xpathNodeSet(NodeCatalog cat, XPathExpression xp)
{
	int i  = 0;
	XPathData[] ed = xp.code;

	NodeSet qset;
	Element test;
	Attribute atb;

	NodeSet next;
	NodeCatalog ncat;
	bool hasIndex;
	XPathData*  pix;
	int  elemIndex;
	while(i < ed.length)
	{
		XPathData* pd = &ed[i];
		i++;

		switch(pd.optype)
		{
		case XPathShort.XP_QNAME:
			if (i < ed.length)
			{
				pix = &ed[i];
				hasIndex = (pix.optype == XPathShort.XP_INDEX);
				if (hasIndex) {
					i++;
					elemIndex = pix.opdata.opIndex;
				}
			}
			else
				hasIndex = false;
			if (qset is null)
			{

				qset = cat.getChildSet(pd.opdata.opString);
				if (qset is null)
				{
					return new NodeSet();
				}
			}
			else {
				next = new NodeSet;
				foreach(icat ; qset.nodes)
				{
					NodeSet chset = icat.getChildSet(pd.opdata.opString);
					if (chset !is null)
					{
						if (hasIndex)
						{
							next.nodes ~= chset.nodes[elemIndex];
						}
						else
							next.nodes ~= chset.nodes;
					}
				}
				qset = next;
			}
			break;
		case XPathShort.XP_ATTR_NAME:
			if (qset is null)
			{
				// return the actual attribute nodes with the name
				test = cat.element;
				if (test is null)
				{
					return null;
				}
				atb = test.getAttributeNode(pd.opdata.opString);
				qset = new NodeSet;
				if (atb !is null)
				{
					qset.nodes ~= new NodeCatalog(atb);
				}
				return qset; // should be last?
			}
			else {
				next = new NodeSet;
				foreach(icat ; qset.nodes)
				{
					test = icat.element;
					if (test !is null)
					{
						atb = test.getAttributeNode(pd.opdata.opString);
						if (atb !is null)
						{
							next.nodes ~= new NodeCatalog(atb);
						}
					}
				}
				return next; // should be last?
			}
		case XPathShort.XP_ALL_ATTR:
			next = new NodeSet;
			if (qset is null)
			{
				qset = next;
				test = cat.element;
				if (test is null)
				{
					return next;
				}
				foreach(Attribute atb ; test)
				{
					qset.nodes ~= new NodeCatalog(atb);
				}
				return qset;
			}
			else {
				foreach(icat ; qset.nodes)
				{
					test = icat.element;
					foreach(Attribute atb ; test)
					{
						next.nodes ~= new NodeCatalog(atb);
					}
				}
				return next;
			}
		case XPathShort.XP_INDEX:
			// should filter current result?
			elemIndex = pd.opdata.opIndex;
			if (qset.nodes.length > elemIndex)
				qset.nodes = qset.nodes[elemIndex .. elemIndex + 1];
			else
				qset.nodes.length = 0;
			break;
		case XPathShort.XP_TEXT:
			if (qset is null)
				return null;
			// replace each node with its text?
			next = new NodeSet;
			foreach(icat ; qset.nodes)
			{
				Element e = cast(Element) icat.node;
				if (e !is null)
				{
					auto n = new Text(e.getTextContent());

					next.nodes ~= new NodeCatalog(n);
				}
			}
			if (next.nodes.length == 0)
				return null;
			qset = next;
			break;
		case XPathShort.XP_ALL:
			// next is all the children
			if (qset is null)
				return null;
			next = new NodeSet;
			foreach(icat ; qset.nodes)
			{
				ElemCatalog elcat = cast(ElemCatalog) icat;
				if (elcat !is null)
					foreach(ns ; elcat.children)
					{
						next.nodes ~= ns.nodes;
					}
			}
			if (next.nodes.length == 0)
				return null;
			qset = next;
			break;
		case XPathShort.XP_SELECT:
			// filter each element based on predicate
			if (qset is null)
				return null;

			PredicateContext ctx;

			next = new NodeSet;

			ctx.size = qset.nodes.length;
			ctx.cop = pd.opdata.opSelect;

			foreach(ipos, icat ; qset.nodes)
			{
				Element e = cast(Element) icat.node;
				if (e !is null)
				{
					ctx.pe = e;
					ctx.pos = ipos;
					if (evaluatePredicate(ctx))
						next.nodes ~= icat;
				}
			}
			if (next.nodes.length == 0)
				return next;
			qset = next;

			break;
		default:
			break;
		}
	}
	return qset;
}

/***
 *    Return parsed XPathExpression from a simple short xpath.
 * 	   / | //  ,  QNAME  ( [predicate] )? ( / , QNAME ([predicate])*
 *
 *
 ***/

	XPathExpression shortXPath(string xpath)
	{
		auto ir = new InputArray!char(xpath);

		auto spi = new XPathParse(ir);
		auto xpe = new XPathExpression();

		string pdata;
		bool   lastsep = false;
		while (!spi.empty)
		{
			XPathShort xps = parseXPathShort(spi, pdata);
			if (xps != XPathShort.XP_SEP)
				lastsep = false;

			switch(xps)
			{
			case XPathShort.XP_DOT:
			case XPathShort.XP_PARDOT:
					break;

			case XPathShort.XP_TEXT:
			case XPathShort.XP_ALL:
					// all children
					xpe.noData(xps);
					break;
			case XPathShort.XP_SEP:
					if (lastsep)
						throw new XPathSyntaxError("too many /");
					lastsep = true;
					break;
			case XPathShort.XP_ATTR_NAME:
					xpe.attrName(pdata);
					break;
			case XPathShort.XP_ALL_ATTR:
					xpe.noData(xps);
					break;
			case XPathShort.XP_QNAME:
					xpe.childElement(pdata);
					break;
			case XPathShort.XP_PREDICATE_BEGIN:
					XPathCompOp pred;
					if (parsePredicate(spi, pred))
						xpe.elemCondition(pred);
					break;
			default:
					break;
			}
		}
		return xpe;
	}


