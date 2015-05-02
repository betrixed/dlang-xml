/**
This is about making XML dcouments just using text strings.

License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Authors: Michael Rynn

Distributed under the Boost Software License, Version 1.0.

This module sees XML as strings for element names, or string pairs for attributes and values,
so it is somewhat independent of the implementation of a DOM.
It gets used by DOM aware implementations.
Each string is output via the delegate StringPutDg.
**/

module xml.util.print;

version=ATTRIBUTE_BLOCK;

import xml.xmlchar;
import std.array;
import std.exception;
import std.conv;
import std.string;
import std.stdint;
import alt.buffer;


template XMLPrint(T)
{
	alias void delegate(const(T)[] s)	StringPutDg;

	alias XmlString[dchar] CharEntityMap;
	static if (is(T==char))
		alias std.conv.text	concats;
	else static if (is(T==wchar))
		alias std.conv.wtext concats;
	else
		alias std.conv.dtext concats;

/* Options to control output */

struct XmlPrintOptions
{

    this(StringPutDg dg)
    {
        putDg = dg;
        indentStep = 2;
        emptyTags = true;
        noComments = false;
        noWhiteSpace = false;
        sortAttributes = true;
        encodeNonASCII = false;
        xversion = 1.0;
    }

    CharEntityMap	charEntities;

    uint	indentStep; // increment for recursion
    bool	emptyTags;  // print empty tag style
    bool	noComments;	// no comment output
    bool	noWhiteSpace; // convert whitespace to character reference
    bool	sortAttributes;
    bool	encodeNonASCII;
    double  xversion;

    StringPutDg		putDg;

    /// delayed entity lookup values
    void configEntities()
    {
        charEntities['<'] = "&lt;";
        charEntities['>'] = "&gt;";
        charEntities['\"'] = "&quot;";
        charEntities['&'] = "&amp;";

        if (noWhiteSpace)
        {
            charEntities[0x0A] = "&#10;";
            charEntities[0x0D] = "&#13;";
            charEntities[0x09] = "&#9;";
        }
        if (xversion > 1.0)
        {
            dchar c;
            for (c = 0x1; c <= 0x1F; c++)
            {
                if (isControlCharRef11(c))
                    charEntities[c] = concats("&#",cast(uint)c,";");
            }
            for (c = 0x7F; c <= 0x9F; c++)
            {
                charEntities[c] = concats("&#",cast(uint)c,";");
            }
        }
    }

}

/// Wrap CDATA and its end around the content

XmlString makeXmlCDATA(XmlString txt)
{
    return concats("<![CDATA[", txt, "]]>");
}

/// Wrap the Xml Processing Instruction

XmlString makeXmlProcessingInstruction(XmlString target, XmlString data)
{
    if (data !is null)
        return concats("<?", target, " ", data, "?>");
    else
        return concats("<?", target," ?>");
}

/// Wrap the text as XML comment

XmlString makeXmlComment(XmlString txt)
{
    return concats("<!--", txt, "-->");
}

/// OutputRange (put). Checks every character to see if needs to be entity encoded.
void encodeCharEntity(P)(auto ref P p, XmlString text, CharEntityMap charEntities)
{
    foreach(dchar d ; text)
    {
        auto ps = d in charEntities;
        if (ps !is null)
            p.put(*ps);
        else
            p.put(d);
    }
}

/// Return character entity encoded version of string
XmlString encodeStdEntity(XmlString text,  CharEntityMap charEntities)
{
	Buffer!T	app;
    encodeCharEntity(app, text,charEntities);
    return to!XmlString(app.peek);
}

/// right justified index
string doIndent(string s, uintptr_t indent)
{
    char[] buf;
    auto slen = s.length;
    buf.length = indent + slen;
    size_t i = 0;
    while( i < indent)
        buf[i++] = ' ';
    buf[i..i+slen] = s[0..slen];
    return assumeUnique(buf);
}

version(TrackCount)
import std.stdio;

/// Recursible XML printer that passes along XMLOutOptions
struct XmlPrinter
{
    uint				    indent;// current indent
    XmlPrintOptions*		options;
    private Buffer!T    	pack; // each indent level with reusable buffer

    // constructor for recursion
    this(ref XmlPrinter tp)
    {
        options = tp.options;
        indent = tp.indent + options.indentStep;
		version(TrackCount)
			pack.setid(format("XmlPrinter pack %s", indent));
    }

	this(this)
	{
		// for when copied as value argument.  pack has reference count
		version(TrackCount)
		{
			//writeln("indent ", indent, " pack refcount ", pack.refcount());
		}
	}


    // append with indent  "...<tag"
    private void appendStartTag(XmlString tag)
    {
        immutable original = pack.length;
        immutable taglen = tag.length;
        pack.length = original + indent + taglen + 1;
        auto buf = pack.toArray[original..$];
        uintptr_t i = indent;
        if (i > 0)
            buf[0..i] = ' ';
        buf[i++] = '<';
        buf[i .. $] = tag[0 .. $];
    }
    // append with indent
    private void appendEndTag(XmlString tag)
    {
        immutable original = pack.length;
        immutable taglen = tag.length;
        pack.length = original + indent + taglen + 3;
        auto buf = pack.toArray[original..$];
        buf[0..indent] = ' ';
        uintptr_t i = indent;
        buf[i++] = '<';
        buf[i++] = '/';
        buf[i .. i + taglen] = tag;
        i += taglen;
        buf[i] = '>';
    }


    XmlString encodeEntity(XmlString value)
    {
        return encodeStdEntity(value, options.charEntities);
    }

    // constructor for starting
    this(ref XmlPrintOptions opt, uint currentIndent = 0)
    {
        indent = currentIndent;
        options = &opt;

        if (options.charEntities.length == 0)
        {
            options.configEntities();
        }
    }

    // string[string] output as XML. There is no encoding here yet.
    // May have to pre-entity encode the AA values.

    @property bool noComments()
    {
        return options.noComments;
    }
    @property bool emptyTags()
    {
        return options.emptyTags;
    }
    @property bool noWhiteSpace()
    {
        return options.noWhiteSpace;
    }

    private void appendAttributes(AttributeMap attr)
    {
        if (attr.length == 0)
            return;
        void output(ref AttributeMap pmap)
        {
            foreach(k,v ; pmap)
            {
                pack.put(' ');
                pack.put(k);
                pack.put('=');
				// By using \", do not have to encode '\'';
                pack.put('\"');
                encodeCharEntity(pack, v, options.charEntities);
                pack.put('\"');
            }
        }

        if (options.sortAttributes)
        {
            if (!attr.sorted)
				attr.sort();
        }
        output(attr);


    }
	void mapToAttributePairs(AttributeMap map, ref AttributeMap ap)
	{
		foreach(n,v ; map)
		{
			ap.put(AttributeMap.BlockRec(n,v));
		}
	}

    /// Element containing attributes and single text content. Encode content.
    void  putTextElement(XmlString ename, XmlString content)
    {
        pack.length = 0;
        pack.reserve(ename.length * 2 + 5 + content.length);
        appendStartTag(ename);
        pack.put('>');
        encodeCharEntity(pack, content, options.charEntities);
		pack.put("</");
		pack.put(ename);
		pack.put('>');
        options.putDg(pack.toArray);
    }
    /// Element containing no attributes and single text content. Encode content.
    void  putTextElement(XmlString ename, ref AttributeMap map, XmlString content)
    {
        pack.length = 0;
        pack.reserve(ename.length * 2 + 5 + content.length);
        appendStartTag(ename);
        if (map.length > 0)
		{
			AttributeMap ap;
			ap.copy(map);
            appendAttributes(ap);
		}
        pack.put('>');
        encodeCharEntity(pack, content, options.charEntities);
		pack.put("</");
		pack.put(ename);
		pack.put('>');
        options.putDg(pack.toArray);
    }
    /// indented start tag without attributes
    void putStartTag(XmlString tag)
    {
        pack.length = 0;
        appendStartTag(tag);
        pack.put('>');
        options.putDg( pack.toArray );
    }
    /// indented start tag with attributes
    void putStartTag(XmlString tag, AttributeMap attr, bool isEmpty)
    {
        pack.length = 0;
        appendStartTag(tag);
        if (attr.length > 0)
		{
			AttributeMap ap;
			ap.copy(attr);
            appendAttributes(ap);
		}
        if (isEmpty)
        {
            if (options.emptyTags)
                pack.put(" />");
            else
            {
                pack.put("></");
                pack.put(tag);
                pack.put('>');
            }
        }
        else
        {
            pack.put('>');
        }
        options.putDg(pack.toArray);
    }

    /// indented empty tag, no attributes
    void putEmptyTag(XmlString tag)
    {
        pack.length = 0;
        if(!options.emptyTags)
        {
            appendStartTag(tag);
            pack.put("></");
            pack.put(tag);
            pack.put('>');
        }
        else
        {
            appendStartTag(tag);
            pack.put(" />");
        }
        options.putDg(pack.toArray);
    }
    /// indented end tag
    void putEndTag(XmlString tag)
    {
        pack.length = 0;
        appendEndTag(tag);
        options.putDg(pack.toArray);
    }

    void putIndent(const(T)[] s)
    {
        pack.length = indent + s.length;
        auto buf = pack.toArray;
        uintptr_t i = indent;
        if(i > 0)
            buf[0..i] = ' ';
        buf[i .. $] = s;
        options.putDg(buf);
    }
}

/// output the XML declaration
void printXmlDeclaration(AttributeMap attr, StringPutDg putOut)
{
    if (attr.length == 0)
        return;

    T[] xmldec;
    Buffer!T	app;


    void putAttribute(XmlString attrname)
    {
        auto pvalue = attrname in attr;
        if (pvalue !is null)
        {
            app.put(' ');
            app.put(attrname);
            app.put("=\"");
            app.put(*pvalue);
            app.put('\"');
        }
    }
    app.put("<?xml");
    putAttribute("version");
    putAttribute("standalone");
    putAttribute("encoding");
    app.put("?>");
    putOut(app.idup);
}

}