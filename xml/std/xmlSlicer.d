// Written in the D programming language.

/**
$(RED Warning: This module is considered out-dated and not up to Phobos'
      current standards. It will remain until we have a suitable replacement,
      but be aware that it will not remain long term.)

Classes and functions for creating and parsing XML

The basic architecture of this module is that there are standalone functions,
classes for constructing an XML document from scratch (Tag, Element and
Document), and also classes for parsing a pre-existing XML file (ElementParser
and DocumentParser). The parsing classes <i>may</i> be used to build a
Document, but that is not their primary purpose. The handling capabilities of
DocumentParser and ElementParser are sufficiently customizable that you can
make them do pretty much whatever you want.

Example: This example creates a DOM (Document Object Model) tree
    from an XML file.
------------------------------------------------------------------------------
import std.xml;
import std.stdio;
import std.string;
import std.file;

// books.xml is used in various samples throughout the Microsoft XML Core
// Services (MSXML) SDK.
//
// See http://msdn2.microsoft.com/en-us/library/ms762271(VS.85).aspx

void main()
{
    string s = cast(string)std.file.read("books.xml");

    // Check for well-formedness
    check(s);

    // Make a DOM tree
    auto doc = new Document(s);

    // Plain-print it
    writeln(doc);
}
------------------------------------------------------------------------------

Example: This example does much the same thing, except that the file is
    deconstructed and reconstructed by hand. This is more work, but the
    techniques involved offer vastly more power.
------------------------------------------------------------------------------
import std.xml;
import std.stdio;
import std.string;

struct Book
{
    string id;
    string author;
    string title;
    string genre;
    string price;
    string pubDate;
    string description;
}

void main()
{
    string s = cast(string)std.file.read("books.xml");

    // Check for well-formedness
    check(s);

    // Take it apart
    Book[] books;

    auto xml = new DocumentParser(s);
    xml.onStartTag["book"] = (ElementParser xml)
    {
        Book book;
        book.id = xml.tag.attr["id"];

        xml.onEndTag["author"]       = (in Element e) { book.author      = e.text(); };
        xml.onEndTag["title"]        = (in Element e) { book.title       = e.text(); };
        xml.onEndTag["genre"]        = (in Element e) { book.genre       = e.text(); };
        xml.onEndTag["price"]        = (in Element e) { book.price       = e.text(); };
        xml.onEndTag["publish-date"] = (in Element e) { book.pubDate     = e.text(); };
        xml.onEndTag["description"]  = (in Element e) { book.description = e.text(); };

        xml.parse();

        books ~= book;
    };
    xml.parse();

    // Put it back together again;
    auto doc = new Document(new Tag("catalog"));
    foreach(book;books)
    {
        auto element = new Element("book");
        element.tag.attr["id"] = book.id;

        element ~= new Element("author",      book.author);
        element ~= new Element("title",       book.title);
        element ~= new Element("genre",       book.genre);
        element ~= new Element("price",       book.price);
        element ~= new Element("publish-date",book.pubDate);
        element ~= new Element("description", book.description);

        doc ~= element;
    }

    // Pretty-print it
    writefln(join(doc.pretty(3),"\n"));
}
-------------------------------------------------------------------------------
Macros:
    WIKI=Phobos/StdXml

Copyright: Copyright Janice Caron 2008 - 2009.
License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors:   Janice Caron, Michael Rynn
Source:    $(PHOBOSSRC std/_xml.d)
*/
/*
         Copyright Janice Caron 2008 - 2009.
Distributed under the Boost Software License, Version 1.0.
   (See accompanying file LICENSE_1_0.txt or copy at
         http://www.boost.org/LICENSE_1_0.txt)
*/
module xml.std.xmlSlicer; // renamed for test comparisons

import std.algorithm : count, startsWith;
import std.array;
import std.ascii;
import std.string;
import std.encoding;
import std.stdio;

/**
	On investigation, using GC_STATS instance counting, it was found that with a big document load (see bigload project),
too many Tag, ElementParser, and Element objects seemed to hang around in GC land. Like fleas on a cat.
Cause unknown, maybe lots of function closures hanging around with references on heap. The GC should be better than this.

This was 'fixed' only by ensuring the transitory nature of such objects. 
The 'Element' object passed on the EndTag event, is guaranteed transitory, by destroy after use.
ElementParser is of course, an enforced transient. 
The explode() method is available on the DOM tree to enforce destruction.

GC_STATS also noted that 3 times as many Tag objects were created as number of Element objects. 
This prompted a implementation alteration.
The Element object no longer has a Tag sub object, but uses direct fields of name, attributes, tag type, tagString.
A TagData structure in the ElementParser eliminated some of the creation and destruction of Tag objects.
ElementParser maintains a local Tag object stack in the parse function, rather than an associative array.

After using this methodology, the bigload test cleared all xmlSlice objects from GC memory.

Design of check(document).  This has the problem that exceptions are thrown for most ordinary results of checks, caught and rethrown.
This technically works, but has slower performance.  It was also a little hard to follow in the code.

In theory a valid XML document should throw no exceptions at all during a check.

In no way will this be a check for more obscure issues.  DOCTYPE is still not supported. 


The check functions were changed to only throw errors if a not well formed condition is encountered.
A check stack of string slices keeps track of the parse check state history.

This is still a relatively 'standalone' XML module
*/

version(GC_STATS)
{
	import xml.util.gcstats;
}
enum cdata = "<![CDATA[";

/**
 * Returns true if the character is a character according to the XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
bool isChar(dchar c) // rule 2
{
    if (c <= 0xD7FF)
    {
        if (c >= 0x20)
            return true;
        switch(c)
        {
        case 0xA:
        case 0x9:
        case 0xD:
            return true;
        default:
            return false;
        }
    }
    else if (0xE000 <= c && c <= 0x10FFFF)
    {
        if ((c & 0x1FFFFE) != 0xFFFE) // U+FFFE and U+FFFF
            return true;
    }
    return false;
}

unittest
{
//  const CharTable=[0x9,0x9,0xA,0xA,0xD,0xD,0x20,0xD7FF,0xE000,0xFFFD,
//        0x10000,0x10FFFF];
    assert(!isChar(cast(dchar)0x8));
    assert( isChar(cast(dchar)0x9));
    assert( isChar(cast(dchar)0xA));
    assert(!isChar(cast(dchar)0xB));
    assert(!isChar(cast(dchar)0xC));
    assert( isChar(cast(dchar)0xD));
    assert(!isChar(cast(dchar)0xE));
    assert(!isChar(cast(dchar)0x1F));
    assert( isChar(cast(dchar)0x20));
    assert( isChar('J'));
    assert( isChar(cast(dchar)0xD7FF));
    assert(!isChar(cast(dchar)0xD800));
    assert(!isChar(cast(dchar)0xDFFF));
    assert( isChar(cast(dchar)0xE000));
    assert( isChar(cast(dchar)0xFFFD));
    assert(!isChar(cast(dchar)0xFFFE));
    assert(!isChar(cast(dchar)0xFFFF));
    assert( isChar(cast(dchar)0x10000));
    assert( isChar(cast(dchar)0x10FFFF));
    assert(!isChar(cast(dchar)0x110000));

    debug (stdxml_TestHardcodedChecks)
    {
        foreach (c; 0 .. dchar.max + 1)
            assert(isChar(c) == lookup(CharTable, c));
    }
}

/**
 * Returns true if the character is whitespace according to the XML standard
 *
 * Only the following characters are considered whitespace in XML - space, tab,
 * carriage return and linefeed
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
bool isSpace(dchar c)
{
    return c == '\u0020' || c == '\u0009' || c == '\u000A' || c == '\u000D';
}

/**
 * Returns true if the character is a digit according to the XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
bool isDigit(dchar c)
{
    if (c <= 0x0039 && c >= 0x0030)
        return true;
    else
        return lookup(DigitTable,c);
}

unittest
{
    debug (stdxml_TestHardcodedChecks)
    {
        foreach (c; 0 .. dchar.max + 1)
            assert(isDigit(c) == lookup(DigitTable, c));
    }
}

/**
 * Returns true if the character is a letter according to the XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
bool isLetter(dchar c) // rule 84
{
    return isIdeographic(c) || isBaseChar(c);
}

/**
 * Returns true if the character is an ideographic character according to the
 * XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
bool isIdeographic(dchar c)
{
    if (c == 0x3007)
        return true;
    if (c <= 0x3029 && c >= 0x3021 )
        return true;
    if (c <= 0x9FA5 && c >= 0x4E00)
        return true;
    return false;
}

unittest
{
    assert(isIdeographic('\u4E00'));
    assert(isIdeographic('\u9FA5'));
    assert(isIdeographic('\u3007'));
    assert(isIdeographic('\u3021'));
    assert(isIdeographic('\u3029'));

    debug (stdxml_TestHardcodedChecks)
    {
        foreach (c; 0 .. dchar.max + 1)
            assert(isIdeographic(c) == lookup(IdeographicTable, c));
    }
}

/**
 * Returns true if the character is a base character according to the XML
 * standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
bool isBaseChar(dchar c)
{
    return lookup(BaseCharTable,c);
}

/**
 * Returns true if the character is a combining character according to the
 * XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
bool isCombiningChar(dchar c)
{
    return lookup(CombiningCharTable,c);
}

/**
 * Returns true if the character is an extender according to the XML standard
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *    c = the character to be tested
 */
bool isExtender(dchar c)
{
    return lookup(ExtenderTable,c);
}

/**
 * Encodes a string by replacing all characters which need to be escaped with
 * appropriate predefined XML entities.
 *
 * encode() escapes certain characters (ampersand, quote, apostrophe, less-than
 * and greater-than), and similarly, decode() unescapes them. These functions
 * are provided for convenience only. You do not need to use them when using
 * the std.xml classes, because then all the encoding and decoding will be done
 * for you automatically.
 *
 * If the string is not modified, the original will be returned.
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *      s = The string to be encoded
 *
 * Returns: The encoded string
 *
 * Examples:
 * --------------
 * writefln(encode("a > b")); // writes "a &gt; b"
 * --------------
 */
S encode(S)(S s)
{
    string r;
    size_t lastI;
    auto result = appender!S();

    foreach (i, c; s)
    {
        switch (c)
        {
        case '&':  r = "&amp;"; break;
        case '"':  r = "&quot;"; break;
        case '\'': r = "&apos;"; break;
        case '<':  r = "&lt;"; break;
        case '>':  r = "&gt;"; break;
        default: continue;
        }
        // Replace with r
        result.put(s[lastI .. i]);
        result.put(r);
        lastI = i + 1;
    }

    if (!result.data.ptr) return s;
    result.put(s[lastI .. $]);
    return result.data;
}

unittest
{
    auto s = "hello";
    assert(encode(s) is s);
    assert(encode("a > b") == "a &gt; b", encode("a > b"));
    assert(encode("a < b") == "a &lt; b");
    assert(encode("don't") == "don&apos;t");
    assert(encode("\"hi\"") == "&quot;hi&quot;", encode("\"hi\""));
    assert(encode("cat & dog") == "cat &amp; dog");
}

void failCheck(string tail, string msg)
{
	throw new Err(tail,msg);
}
void checkCharRef(ref string s, out dchar c) // rule 66
{


	checkLiteral("&#",s);
	c = 0;
	int radix = 10;
	if (s.length != 0 && s[0] == 'x')
	{
		s = s[1..$];
		radix = 16;
	}
	if (s.length == 0)
		failCheck(s,"unterminated character reference");
	if (s[0] == ';')
		failCheck(s,"character reference must have at least one digit");
	while (s.length != 0)
	{
		char d = s[0];
		int n = 0;
		switch(d)
		{
			case 'F','f': ++n;      goto case;
			case 'E','e': ++n;      goto case;
			case 'D','d': ++n;      goto case;
			case 'C','c': ++n;      goto case;
			case 'B','b': ++n;      goto case;
			case 'A','a': ++n;      goto case;
			case '9':     ++n;      goto case;
			case '8':     ++n;      goto case;
			case '7':     ++n;      goto case;
			case '6':     ++n;      goto case;
			case '5':     ++n;      goto case;
			case '4':     ++n;      goto case;
			case '3':     ++n;      goto case;
			case '2':     ++n;      goto case;
			case '1':     ++n;      goto case;
			case '0':     break;
			default: n = 100; break;
		}
		if (n >= radix) break;
		c *= radix;
		c += n;
		s = s[1..$];
	}
	if (!isChar(c)) 
		failCheck(s,format("U+%04X is not a legal character",c));
	if (s.length == 0 || s[0] != ';') 
		failCheck(s,"expected ;");
	else 
		s = s[1..$];
}
/**
 * Mode to use for decoding.
 *
 * $(DDOC_ENUM_MEMBERS NONE) Do not decode
 * $(DDOC_ENUM_MEMBERS LOOSE) Decode, but ignore errors
 * $(DDOC_ENUM_MEMBERS STRICT) Decode, and throw exception on error
 */
enum DecodeMode
{
    NONE, LOOSE, STRICT
}

/**
 * Decodes a string by unescaping all predefined XML entities.
 *
 * encode() escapes certain characters (ampersand, quote, apostrophe, less-than
 * and greater-than), and similarly, decode() unescapes them. These functions
 * are provided for convenience only. You do not need to use them when using
 * the std.xml classes, because then all the encoding and decoding will be done
 * for you automatically.
 *
 * This function decodes the entities &amp;amp;, &amp;quot;, &amp;apos;,
 * &amp;lt; and &amp;gt,
 * as well as decimal and hexadecimal entities such as &amp;#x20AC;
 *
 * If the string does not contain an ampersand, the original will be returned.
 *
 * Note that the "mode" parameter can be one of DecodeMode.NONE (do not
 * decode), DecodeMode.LOOSE (decode, but ignore errors), or DecodeMode.STRICT
 * (decode, and throw a DecodeException in the event of an error).
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Params:
 *      s = The string to be decoded
 *      mode = (optional) Mode to use for decoding. (Defaults to LOOSE).
 *
 * Throws: DecodeException if mode == DecodeMode.STRICT and decode fails
 *
 * Returns: The decoded string
 *
 * Examples:
 * --------------
 * writefln(decode("a &gt; b")); // writes "a > b"
 * --------------
 */
string decode(string s, DecodeMode mode=DecodeMode.LOOSE)
{
    import std.utf : encode;

    if (mode == DecodeMode.NONE) return s;

    char[] buffer;
    foreach (ref i; 0 .. s.length)
    {
        char c = s[i];
        if (c != '&')
        {
            if (buffer.length != 0) buffer ~= c;
        }
        else
        {
            if (buffer.length == 0)
            {
                buffer = s[0 .. i].dup;
            }
            if (startsWith(s[i..$],"&#"))
            {
                try
                {
                    dchar d;
                    string t = s[i..$];
                    checkCharRef(t, d);
                    char[4] temp;
                    buffer ~= temp[0 .. std.utf.encode(temp, d)];
                    i = s.length - t.length - 1;
                }
                catch(Err e)
                {
                    if (mode == DecodeMode.STRICT)
                        throw new DecodeException("Unescaped &");
                    buffer ~= '&';
                }
            }
            else if (startsWith(s[i..$],"&amp;" )) { buffer ~= '&';  i += 4; }
            else if (startsWith(s[i..$],"&quot;")) { buffer ~= '"';  i += 5; }
            else if (startsWith(s[i..$],"&apos;")) { buffer ~= '\''; i += 5; }
            else if (startsWith(s[i..$],"&lt;"  )) { buffer ~= '<';  i += 3; }
            else if (startsWith(s[i..$],"&gt;"  )) { buffer ~= '>';  i += 3; }
            else
            {
                if (mode == DecodeMode.STRICT)
                    throw new DecodeException("Unescaped &");
                buffer ~= '&';
            }
        }
    }
    return (buffer.length == 0) ? s : cast(string)buffer;
}

unittest
{
    void assertNot(string s)
    {
        bool b = false;
        try { decode(s,DecodeMode.STRICT); }
        catch (DecodeException e) { b = true; }
        assert(b,s);
    }

    // Assert that things that should work, do
    auto s = "hello";
    assert(decode(s,                DecodeMode.STRICT) is s);
    assert(decode("a &gt; b",       DecodeMode.STRICT) == "a > b");
    assert(decode("a &lt; b",       DecodeMode.STRICT) == "a < b");
    assert(decode("don&apos;t",     DecodeMode.STRICT) == "don't");
    assert(decode("&quot;hi&quot;", DecodeMode.STRICT) == "\"hi\"");
    assert(decode("cat &amp; dog",  DecodeMode.STRICT) == "cat & dog");
    assert(decode("&#42;",          DecodeMode.STRICT) == "*");
    assert(decode("&#x2A;",         DecodeMode.STRICT) == "*");
    assert(decode("cat & dog",      DecodeMode.LOOSE) == "cat & dog");
    assert(decode("a &gt b",        DecodeMode.LOOSE) == "a &gt b");
    assert(decode("&#;",            DecodeMode.LOOSE) == "&#;");
    assert(decode("&#x;",           DecodeMode.LOOSE) == "&#x;");
    assert(decode("&#2G;",          DecodeMode.LOOSE) == "&#2G;");
    assert(decode("&#x2G;",         DecodeMode.LOOSE) == "&#x2G;");

    // Assert that things that shouldn't work, don't
    assertNot("cat & dog");
    assertNot("a &gt b");
    assertNot("&#;");
    assertNot("&#x;");
    assertNot("&#2G;");
    assertNot("&#x2G;");
}

/**
 * Class representing an XML document.
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 */
class Document : Element
{
    /**
     * Contains all text which occurs before the root element.
     * Defaults to &lt;?xml version="1.0"?&gt;
     */
    string prolog = "<?xml version=\"1.0\"?>";
    /**
     * Contains all text which occurs after the root element.
     * Defaults to the empty string
     */
    string epilog;

    /**
     * Constructs a Document by parsing XML text.
     *
     * This function creates a complete DOM (Document Object Model) tree.
     *
     * The input to this function MUST be valid XML.
     * This is enforced by DocumentParser's in contract.
     *
     * Params:
     *      s = the complete XML text.
     */
    this(string s)
    in
    {
        assert(s.length != 0);
    }
    body
    {
        auto xml = new DocumentParser(s);
        string tagString = xml.tag.tagString;

        this(xml.tag);
        prolog = s[0 .. tagString.ptr - s.ptr];
        parse(xml);
        epilog = *xml.s;
    }

    /**
     * Constructs a Document from a Tag.
     *
     * Params:
     *      tag = the start tag of the document.
     */
    this(const(Tag) tag)
    {
        super(tag);
    }

    const
    {
        /**
         * Compares two Documents for equality
         *
         * Examples:
         * --------------
         * Document d1,d2;
         * if (d1 == d2) { }
         * --------------
         */
        override bool opEquals(Object o)
        {
            const doc = toType!(const Document)(o);
            return
                (prolog != doc.prolog            ) ? false : (
                (super  != cast(const Element)doc) ? false : (
                (epilog != doc.epilog            ) ? false : (
            true )));
        }

        /**
         * Compares two Documents
         *
         * You should rarely need to call this function. It exists so that
         * Documents can be used as associative array keys.
         *
         * Examples:
         * --------------
         * Document d1,d2;
         * if (d1 < d2) { }
         * --------------
         */
        override int opCmp(Object o)
        {
            const doc = toType!(const Document)(o);
            return
                ((prolog != doc.prolog            )
                    ? ( prolog < doc.prolog             ? -1 : 1 ) :
                ((super  != cast(const Element)doc)
                    ? ( cast()super  < cast()cast(const Element)doc ? -1 : 1 ) :
                ((epilog != doc.epilog            )
                    ? ( epilog < doc.epilog             ? -1 : 1 ) :
            0 )));
        }

        /**
         * Returns the hash of a Document
         *
         * You should rarely need to call this function. It exists so that
         * Documents can be used as associative array keys.
         */
        override size_t toHash() @trusted
        {
            return hash(prolog, hash(epilog, (cast()super).toHash()));
        }

        /**
         * Returns the string representation of a Document. (That is, the
         * complete XML of a document).
         */
        override string toString()
        {
            return prolog ~ super.toString() ~ epilog;
        }
    }
}

/**
 * Class representing an XML element.
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 */
class Element : Item
{
	string tagName;
	string tagString;
    string[string] attribute;
	TagType			etype;

    Item[] items; /// The element's items
    Text[] texts; /// The element's text items
    CData[] cdatas; /// The element's CData items
    Comment[] comments; /// The element's comments
    ProcessingInstruction[] pis; /// The element's processing instructions
    Element[] elements; /// The element's child elements

	version(GC_STATS)
    {
        mixin GC_statistics;
        static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
    }

	override void explode()
	{
		tagName = null;
		attribute = null;
		tagString = null;

		foreach ( item ; items)
		{
			item.explode();
			destroy(item);
		}	
		items = [];
		texts = [];
		cdatas = [];
		comments = [];
		elements = [];
		pis = [];


	}

	version(GC_STATS)
	{
		~this()
		{
			gcStatsSum.dec();
			

		}
	}
    /**
     * Constructs an Element given a name and a string to be used as a Text
     * interior.
     *
     * Params:
     *      name = the name of the element.
     *      interior = (optional) the string interior.
     *
     * Examples:
     * -------------------------------------------------------
     * auto element = new Element("title","Serenity")
     *     // constructs the element <title>Serenity</title>
     * -------------------------------------------------------
     */
    this(string name, string interior=null)
    {
        this(new Tag(name));
        if (interior.length != 0) opCatAssign(new Text(interior));
		version (GC_STATS)
			gcStatsSum.inc();

    }

    /**
     * Constructs an Element from a Tag.
     *
     * Params:
     *      tag_ = the start or empty tag of the element.
     */
    this(const(Tag) tag_)
    {
        tagName = tag_.name;
        foreach(k,v;tag_.attr) attribute[k] = v;
        tagString = tag_.tagString;
		etype = tag_.type;

		version (GC_STATS)
			gcStatsSum.inc();

    }
    this(const ref TagData tag_)
    {
        tagName = tag_.name;
        foreach(k,v;tag_.attr) attribute[k] = v;
        tagString = tag_.tagString;
		etype = tag_.type;

		version (GC_STATS)
			gcStatsSum.inc();

    }
    /**
     * Append a text item to the interior of this element
     *
     * Params:
     *      item = the item you wish to append.
     *
     * Examples:
     * --------------
     * Element element;
     * element ~= new Text("hello");
     * --------------
     */
    void opCatAssign(Text item)
    {
        texts ~= item;
        appendItem(item);
    }

    /**
     * Append a CData item to the interior of this element
     *
     * Params:
     *      item = the item you wish to append.
     *
     * Examples:
     * --------------
     * Element element;
     * element ~= new CData("hello");
     * --------------
     */
    void opCatAssign(CData item)
    {
        cdatas ~= item;
        appendItem(item);
    }

    /**
     * Append a comment to the interior of this element
     *
     * Params:
     *      item = the item you wish to append.
     *
     * Examples:
     * --------------
     * Element element;
     * element ~= new Comment("hello");
     * --------------
     */
    void opCatAssign(Comment item)
    {
        comments ~= item;
        appendItem(item);
    }

    /**
     * Append a processing instruction to the interior of this element
     *
     * Params:
     *      item = the item you wish to append.
     *
     * Examples:
     * --------------
     * Element element;
     * element ~= new ProcessingInstruction("hello");
     * --------------
     */
    void opCatAssign(ProcessingInstruction item)
    {
        pis ~= item;
        appendItem(item);
    }

    /**
     * Append a complete element to the interior of this element
     *
     * Params:
     *      item = the item you wish to append.
     *
     * Examples:
     * --------------
     * Element element;
     * Element other = new Element("br");
     * element ~= other;
     *    // appends element representing <br />
     * --------------
     */
    void opCatAssign(Element item)
    {
        elements ~= item;
        appendItem(item);
    }

    private void appendItem(Item item)
    {
        items ~= item;
        if (etype == TagType.EMPTY && !item.isEmptyXML)
            etype = TagType.START;
    }

    private void parse(ElementParser xml)
    {
        xml.onText = (string s) { opCatAssign(new Text(s)); };
        xml.onCData = (string s) { opCatAssign(new CData(s)); };
        xml.onComment = (string s) { opCatAssign(new Comment(s)); };
        xml.onPI = (string s) { opCatAssign(new ProcessingInstruction(s)); };

        xml.onStartTag[null] = (ElementParser xml)
        {
            auto e = new Element(xml.tag);
            e.parse(xml);
            opCatAssign(e);
        };

        xml.parse();
    }

    /**
     * Compares two Elements for equality
     *
     * Examples:
     * --------------
     * Element e1,e2;
     * if (e1 == e2) { }
     * --------------
     */
    override bool opEquals(Object o)
    {
        const element = toType!(const Element)(o);
        auto len = items.length;
        if (len != element.items.length) return false;
        foreach (i; 0 .. len)
        {
            if (!items[i].opEquals(cast()element.items[i])) return false;
        }
        return true;
    }

    /**
     * Compares two Elements
     *
     * You should rarely need to call this function. It exists so that Elements
     * can be used as associative array keys.
     *
     * Examples:
     * --------------
     * Element e1,e2;
     * if (e1 < e2) { }
     * --------------
     */
    override int opCmp(Object o)
    {
        const element = toType!(const Element)(o);
        for (uint i=0; ; ++i)
        {
            if (i == items.length && i == element.items.length) return 0;
            if (i == items.length) return -1;
            if (i == element.items.length) return 1;
            if (items[i] != element.items[i])
                return items[i].opCmp(cast()element.items[i]);
        }
    }

    /**
     * Returns the hash of an Element
     *
     * You should rarely need to call this function. It exists so that Elements
     * can be used as associative array keys.
     */
    override size_t toHash() const
    {
		size_t hash =  typeid(tagName).getHash(&tagName);
        foreach(item;items) hash += item.toHash();
        return hash;
    }

    const
    {
        /**
         * Returns the decoded interior of an element.
         *
         * The element is assumed to contain text <i>only</i>. So, for
         * example, given XML such as "&lt;title&gt;Good &amp;amp;
         * Bad&lt;/title&gt;", will return "Good &amp; Bad".
         *
         * Params:
         *      mode = (optional) Mode to use for decoding. (Defaults to LOOSE).
         *
         * Throws: DecodeException if decode fails
         */
        string text(DecodeMode mode=DecodeMode.LOOSE)
        {
            string buffer;
            foreach(item;items)
            {
                Text t = cast(Text)item;
                if (t is null) throw new DecodeException(item.toString());
                buffer ~= decode(t.toString(),mode);
            }
            return buffer;
        }

        /**
         * Returns an indented string representation of this item
         *
         * Params:
         *      indent = (optional) number of spaces by which to indent this
         *          element. Defaults to 2.
         */
        override string[] pretty(uint indent=2)
        {

            if (isEmptyXML) return [ toEmptyString() ];

            if (items.length == 1)
            {
                Text t = cast(Text)(items[0]);
                if (t !is null)
                {
                    return [toStartString() ~ t.toString() ~ toEndString()];
                }
            }

            string[] a = [ toStartString() ];
            foreach(item;items)
            {
                string[] b = item.pretty(indent);
                foreach(s;b)
                {
                    a ~= rightJustify(s,count(s) + indent);
                }
            }
            a ~= toEndString();
            return a;
        }

        /**
         * Returns the string representation of an Element
         *
         * Examples:
         * --------------
         * auto element = new Element("br");
         * writefln(element.toString()); // writes "<br />"
         * --------------
         */
        override string toString()
        {
            if (isEmptyXML) return toEmptyString();

            string buffer = toStartString();
            foreach (item;items) { buffer ~= item.toString(); }
            buffer ~= toEndString();
            return buffer;
        }

        override @property bool isEmptyXML() { return items.length == 0; }
    }

	private {
		string toNonEndString() const
		{
			string s = "<" ~ tagName;
			foreach(key,val;attribute)
				s ~= format(" %s=\"%s\"",key,encode(val));
			return s;
		}

		string toStartString()  const { return toNonEndString() ~ ">"; }

		string toEndString()  const { return "</" ~ tagName ~ ">"; }

		string toEmptyString()  const { return toNonEndString() ~ " />"; }
	}
}

/**
 * Tag types.
 *
 * $(DDOC_ENUM_MEMBERS START) Used for start tags
 * $(DDOC_ENUM_MEMBERS END) Used for end tags
 * $(DDOC_ENUM_MEMBERS EMPTY) Used for empty tags
 *
 */
enum TagType { START, END, EMPTY }

/**
 * Class representing an XML tag.
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * The class invariant guarantees
 * <ul>
 * <li> that $(B type) is a valid enum TagType value</li>
 * <li> that $(B name) consists of valid characters</li>
 * <li> that each attribute name consists of valid characters</li>
 * </ul>
 */

// just for the parse
struct TagData {
	TagType type = TagType.START;   /// Type of tag
    string name;                    /// Tag name
    string[string] attr;            /// Associative array of attributes
    private string tagString;

	@property bool isStart() const { return type == TagType.START; }

	@property bool isEnd() const  { return type == TagType.END;   }

	@property bool isEmpty() const { return type == TagType.EMPTY; }

	private this(ref string s, bool dummy)
    {
        tagString = s;
        try
        {
            reqc(s,'<');
            if (optc(s,'/')) type = TagType.END;
            name = munch(s,"^/>"~whitespace);
            munch(s,whitespace);
            while(s.length > 0 && s[0] != '>' && s[0] != '/')
            {
                string key = munch(s,"^="~whitespace);
                munch(s,whitespace);
                reqc(s,'=');
                munch(s,whitespace);
                reqc(s,'"');
                string val = decode(munch(s,"^\""), DecodeMode.LOOSE);
                reqc(s,'"');
                munch(s,whitespace);
                attr[key] = val;
            }
            if (optc(s,'/'))
            {
                if (type == TagType.END) throw new TagException("");
                type = TagType.EMPTY;
            }
            reqc(s,'>');
            tagString.length = (s.ptr - tagString.ptr);
        }
        catch(XMLException e)
        {
            tagString.length = (s.ptr - tagString.ptr);
            throw new TagException(tagString);
        }
    }

}

class Tag
{
    TagType type = TagType.START;   /// Type of tag
    string name;                    /// Tag name
    string[string] attr;            /// Associative array of attributes
    private string tagString;
	version(GC_STATS)
    {
        mixin GC_statistics;
        static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
		/// construct
		version(GC_STATS)
		{
			~this()
			{
				gcStatsSum.dec();
				attr = null;
				tagString = null;
				name = null;
			}
		}



		this()
		{
			version(GC_STATS)
				gcStatsSum.inc();
		}
    }
	this(ref TagData c)
	{
		version(GC_STATS)
			gcStatsSum.inc();
		attr = c.attr;
		tagString = c.tagString;
		type = c.type;
		name = c.name;
	}
	void explode()
	{
		tagString = [];
		foreach(k ; attr.byKey())
		{
			attr.remove(k);
		}
	}

    /**
     * Constructs an instance of Tag with a specified name and type
     *
     * The constructor does not initialize the attributes. To initialize the
     * attributes, you access the $(B attr) member variable.
     *
     * Params:
     *      name = the Tag's name
     *      type = (optional) the Tag's type. If omitted, defaults to
     *          TagType.START.
     *
     * Examples:
     * --------------
     * auto tag = new Tag("img",Tag.EMPTY);
     * tag.attr["src"] = "http://example.com/example.jpg";
     * --------------
     */
    this(string name, TagType type=TagType.START)
    {
        this.name = name;
        this.type = type;
		version(GC_STATS)
			gcStatsSum.inc();

    }

    /* Private constructor (so don't ddoc this!)
     *
     * Constructs a Tag by parsing the string representation, e.g. "<html>".
     *
     * The string is passed by reference, and is advanced over all characters
     * consumed.
     *
     * The second parameter is a dummy parameter only, required solely to
     * distinguish this constructor from the public one.
     */


    const
    {
        /**
         * Compares two Tags for equality
         *
         * You should rarely need to call this function. It exists so that Tags
         * can be used as associative array keys.
         *
         * Examples:
         * --------------
         * Tag tag1,tag2
         * if (tag1 == tag2) { }
         * --------------
         */
        override bool opEquals(Object o)
        {
            const tag = toType!(const Tag)(o);
            return
                (name != tag.name) ? false : (
                (attr != tag.attr) ? false : (
                (type != tag.type) ? false : (
            true )));
        }

        /**
         * Compares two Tags
         *
         * Examples:
         * --------------
         * Tag tag1,tag2
         * if (tag1 < tag2) { }
         * --------------
         */
        override int opCmp(Object o)
        {
            const tag = toType!(const Tag)(o);
            // Note that attr is an AA, so the comparison is nonsensical (bug 10381)
            return
                ((name != tag.name) ? ( name < tag.name ? -1 : 1 ) :
                ((attr != tag.attr) ? ( cast(void *)attr < cast(void*)tag.attr ? -1 : 1 ) :
                ((type != tag.type) ? ( type < tag.type ? -1 : 1 ) :
            0 )));
        }

        /**
         * Returns the hash of a Tag
         *
         * You should rarely need to call this function. It exists so that Tags
         * can be used as associative array keys.
         */
        override size_t toHash()
        {
            return typeid(name).getHash(&name);
        }

        /**
         * Returns the string representation of a Tag
         *
         * Examples:
         * --------------
         * auto tag = new Tag("book",TagType.START);
         * writefln(tag.toString()); // writes "<book>"
         * --------------
         */
        override string toString()
        {
            if (isEmpty) return toEmptyString();
            return (isEnd) ? toEndString() : toStartString();
        }

        private
        {
			string toNonEndString() const
			{
				string s = "<" ~ name;
				foreach(key,val;attr)
					s ~= format(" %s=\"%s\"",key,encode(val));
				return s;
			}

			string toStartString()  const { return toNonEndString() ~ ">"; }

			string toEndString()  const { return "</" ~ name ~ ">"; }

			string toEmptyString()  const { return toNonEndString() ~ " />"; }
        }

        /**
         * Returns true if the Tag is a start tag
         *
         * Examples:
         * --------------
         * if (tag.isStart) { }
         * --------------
         */
        @property bool isStart() const { return type == TagType.START; }

        /**
         * Returns true if the Tag is an end tag
         *
         * Examples:
         * --------------
         * if (tag.isEnd) { }
         * --------------
         */
        @property bool isEnd() const  { return type == TagType.END;   }

        /**
         * Returns true if the Tag is an empty tag
         *
         * Examples:
         * --------------
         * if (tag.isEmpty) { }
         * --------------
         */
        @property bool isEmpty() const { return type == TagType.EMPTY; }
    }
}

/**
 * Class representing a comment
 */
class Comment : Item
{
    private string content;

    /**
     * Construct a comment
     *
     * Params:
     *      content = the body of the comment
     *
     * Throws: CommentException if the comment body is illegal (contains "--"
     * or exactly equals "-")
     *
     * Examples:
     * --------------
     * auto item = new Comment("This is a comment");
     *    // constructs <!--This is a comment-->
     * --------------
     */
    this(string content)
    {
        if (content == "-" || content.indexOf("==") != -1)
            throw new CommentException(content);
        this.content = content;
    }

    /**
     * Compares two comments for equality
     *
     * Examples:
     * --------------
     * Comment item1,item2;
     * if (item1 == item2) { }
     * --------------
     */
    override bool opEquals(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(Comment)item;
        return t !is null && content == t.content;
    }

    /**
     * Compares two comments
     *
     * You should rarely need to call this function. It exists so that Comments
     * can be used as associative array keys.
     *
     * Examples:
     * --------------
     * Comment item1,item2;
     * if (item1 < item2) { }
     * --------------
     */
    override int opCmp(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(Comment)item;
        return t !is null && (content != t.content
            ? (content < t.content ? -1 : 1 ) : 0 );
    }

    /**
     * Returns the hash of a Comment
     *
     * You should rarely need to call this function. It exists so that Comments
     * can be used as associative array keys.
     */
    override size_t toHash() const { return hash(content); }

    /**
     * Returns a string representation of this comment
     */
    override string toString() const { return "<!--" ~ content ~ "-->"; }

    override @property bool isEmptyXML() const { return false; } /// Returns false always
}

/**
 * Class representing a Character Data section
 */
class CData : Item
{
    private string content;

    /**
     * Construct a character data section
     *
     * Params:
     *      content = the body of the character data segment
     *
     * Throws: CDataException if the segment body is illegal (contains "]]>")
     *
     * Examples:
     * --------------
     * auto item = new CData("<b>hello</b>");
     *    // constructs <![CDATA[<b>hello</b>]]>
     * --------------
     */
    this(string content)
    {
        if (content.indexOf("]]>") != -1) throw new CDataException(content);
        this.content = content;
    }

    /**
     * Compares two CDatas for equality
     *
     * Examples:
     * --------------
     * CData item1,item2;
     * if (item1 == item2) { }
     * --------------
     */
    override bool opEquals(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(CData)item;
        return t !is null && content == t.content;
    }

    /**
     * Compares two CDatas
     *
     * You should rarely need to call this function. It exists so that CDatas
     * can be used as associative array keys.
     *
     * Examples:
     * --------------
     * CData item1,item2;
     * if (item1 < item2) { }
     * --------------
     */
    override int opCmp(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(CData)item;
        return t !is null && (content != t.content
            ? (content < t.content ? -1 : 1 ) : 0 );
    }

    /**
     * Returns the hash of a CData
     *
     * You should rarely need to call this function. It exists so that CDatas
     * can be used as associative array keys.
     */
    override size_t toHash() const { return hash(content); }

    /**
     * Returns a string representation of this CData section
     */
    override string toString() const { return cdata ~ content ~ "]]>"; }

    override @property bool isEmptyXML() const { return false; } /// Returns false always
}

/**
 * Class representing a text (aka Parsed Character Data) section
 */
class Text : Item
{
    private string content;

    /**
     * Construct a text (aka PCData) section
     *
     * Params:
     *      content = the text. This function encodes the text before
     *      insertion, so it is safe to insert any text
     *
     * Examples:
     * --------------
     * auto Text = new CData("a < b");
     *    // constructs a &lt; b
     * --------------
     */
    this(string content)
    {
        this.content = encode(content);
    }

    /**
     * Compares two text sections for equality
     *
     * Examples:
     * --------------
     * Text item1,item2;
     * if (item1 == item2) { }
     * --------------
     */
    override bool opEquals(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(Text)item;
        return t !is null && content == t.content;
    }

    /**
     * Compares two text sections
     *
     * You should rarely need to call this function. It exists so that Texts
     * can be used as associative array keys.
     *
     * Examples:
     * --------------
     * Text item1,item2;
     * if (item1 < item2) { }
     * --------------
     */
    override int opCmp(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(Text)item;
        return t !is null
            && (content != t.content ? (content < t.content ? -1 : 1 ) : 0 );
    }

    /**
     * Returns the hash of a text section
     *
     * You should rarely need to call this function. It exists so that Texts
     * can be used as associative array keys.
     */
    override size_t toHash() const { return hash(content); }

    /**
     * Returns a string representation of this Text section
     */
    override string toString() const { return content; }

    /**
     * Returns true if the content is the empty string
     */
    override @property bool isEmptyXML() const { return content.length == 0; }
}

/**
 * Class representing an XML Instruction section
 */
class XMLInstruction : Item
{
    private string content;

    /**
     * Construct an XML Instruction section
     *
     * Params:
     *      content = the body of the instruction segment
     *
     * Throws: XIException if the segment body is illegal (contains ">")
     *
     * Examples:
     * --------------
     * auto item = new XMLInstruction("ATTLIST");
     *    // constructs <!ATTLIST>
     * --------------
     */
    this(string content)
    {
        if (content.indexOf(">") != -1) throw new XIException(content);
        this.content = content;
    }

    /**
     * Compares two XML instructions for equality
     *
     * Examples:
     * --------------
     * XMLInstruction item1,item2;
     * if (item1 == item2) { }
     * --------------
     */
    override bool opEquals(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(XMLInstruction)item;
        return t !is null && content == t.content;
    }

    /**
     * Compares two XML instructions
     *
     * You should rarely need to call this function. It exists so that
     * XmlInstructions can be used as associative array keys.
     *
     * Examples:
     * --------------
     * XMLInstruction item1,item2;
     * if (item1 < item2) { }
     * --------------
     */
    override int opCmp(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(XMLInstruction)item;
        return t !is null
            && (content != t.content ? (content < t.content ? -1 : 1 ) : 0 );
    }

    /**
     * Returns the hash of an XMLInstruction
     *
     * You should rarely need to call this function. It exists so that
     * XmlInstructions can be used as associative array keys.
     */
    override size_t toHash() const { return hash(content); }

    /**
     * Returns a string representation of this XmlInstruction
     */
    override string toString() const { return "<!" ~ content ~ ">"; }

    override @property bool isEmptyXML() const { return false; } /// Returns false always
}

/**
 * Class representing a Processing Instruction section
 */
class ProcessingInstruction : Item
{
    private string content;

    /**
     * Construct a Processing Instruction section
     *
     * Params:
     *      content = the body of the instruction segment
     *
     * Throws: PIException if the segment body is illegal (contains "?>")
     *
     * Examples:
     * --------------
     * auto item = new ProcessingInstruction("php");
     *    // constructs <?php?>
     * --------------
     */
    this(string content)
    {
        if (content.indexOf("?>") != -1) throw new PIException(content);
        this.content = content;
    }

    /**
     * Compares two processing instructions for equality
     *
     * Examples:
     * --------------
     * ProcessingInstruction item1,item2;
     * if (item1 == item2) { }
     * --------------
     */
    override bool opEquals(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(ProcessingInstruction)item;
        return t !is null && content == t.content;
    }

    /**
     * Compares two processing instructions
     *
     * You should rarely need to call this function. It exists so that
     * ProcessingInstructions can be used as associative array keys.
     *
     * Examples:
     * --------------
     * ProcessingInstruction item1,item2;
     * if (item1 < item2) { }
     * --------------
     */
    override int opCmp(Object o)
    {
        const item = toType!(const Item)(o);
        const t = cast(ProcessingInstruction)item;
        return t !is null
            && (content != t.content ? (content < t.content ? -1 : 1 ) : 0 );
    }

    /**
     * Returns the hash of a ProcessingInstruction
     *
     * You should rarely need to call this function. It exists so that
     * ProcessingInstructions can be used as associative array keys.
     */
    override size_t toHash() const { return hash(content); }

    /**
     * Returns a string representation of this ProcessingInstruction
     */
    override string toString() const { return "<?" ~ content ~ "?>"; }

    override @property bool isEmptyXML() const { return false; } /// Returns false always
}

/**
 * Abstract base class for XML items
 */
abstract class Item
{
	version(GC_STATS)
    {
        mixin GC_statistics;
        static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
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
    }

    /// Compares with another Item of same type for equality
    abstract override bool opEquals(Object o);

    /// Compares with another Item of same type
    abstract override int opCmp(Object o);

    /// Returns the hash of this item
    abstract override size_t toHash() const;

    /// Returns a string representation of this item
    abstract override string toString() const;

    /**
     * Returns an indented string representation of this item
     *
     * Params:
     *      indent = number of spaces by which to indent child elements
     */
    string[] pretty(uint indent) const
    {
        string s = strip(toString());
        return s.length == 0 ? [] : [ s ];
    }

    /// Returns true if the item represents empty XML text
    abstract @property bool isEmptyXML() const;

	void explode(){}
}

/**
 * Class for parsing an XML Document.
 *
 * This is a subclass of ElementParser. Most of the useful functions are
 * documented there.
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Bugs:
 *      Currently only supports UTF documents.
 *
 *      If there is an encoding attribute in the prolog, it is ignored.
 *
 */
class DocumentParser : ElementParser
{
    string xmlText;

    /**
     * Constructs a DocumentParser.
     *
     * The input to this function MUST be valid XML.
     * This is enforced by the function's in contract.
     *
     * Params:
     *      xmlText_ = the entire XML document as text
     *
     */
    this(string xmlText_)
    in
    {
        assert(xmlText_.length != 0);
        /* // takes far too long
		try
        {
            // Confirm that the input is valid XML

            check(xmlText_);
        }
        catch (CheckException e)
        {
            // And if it's not, tell the user why not
            assert(false, "\n" ~ e.toString());
        }
		*/
    }
    body
    {
        xmlText = xmlText_;
        s = &xmlText;
        super();    // Initialize everything
        parse();    // Parse through the root tag (but not beyond)
    }
}

/**
 * Class for parsing an XML element.
 *
 * Standards: $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
 *
 * Note that you cannot construct instances of this class directly. You can
 * construct a DocumentParser (which is a subclass of ElementParser), but
 * otherwise, Instances of ElementParser will be created for you by the
 * library, and passed your way via onStartTag handlers.
 *
 */
class ElementParser
{
	version(GC_STATS)
    {
        mixin GC_statistics;
        static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
    }

	void explode()
	{
		destroy(tag_);
		elementStart = null;
		s = null;
		commentHandler = null;
		cdataHandler = null;
		xiHandler = null;
		piHandler = null;
		rawTextHandler = null;
		textHandler = null;
		if (onStartTag !is null)
		{
			foreach(sh ; onStartTag.byKey())
			{
				onStartTag.remove(sh);
			}
		}
		onStartTag = null;
	}

	version(GC_STATS)
	{
		~this()
		{
			explode();
			gcStatsSum.dec();
		}
	}
    alias Handler = void delegate(string);
    alias ElementHandler = void delegate(in Element element);
    alias ParserHandler = void delegate(ElementParser parser);

    private
    {
        Tag tag_;
        string elementStart;
        string* s;

        Handler commentHandler = null;
        Handler cdataHandler = null;
        Handler xiHandler = null;
        Handler piHandler = null;
        Handler rawTextHandler = null;
        Handler textHandler = null;

        // Private constructor for start tags
        this(ElementParser parent, ref TagData t)
        {
            s = parent.s;
            this();
            tag_ = new Tag(t);
        }

        // Private constructor for empty tags
        this(ref TagData t, string* xml)
        {
            s = xml;
            this();
			tag_ = new Tag(t);
			
        }
    }

    /**
     * The Tag at the start of the element being parsed. You can read this to
     * determine the tag's name and attributes.
     */
    @property const(Tag) tag() const { return tag_; }

    /**
     * Register a handler which will be called whenever a start tag is
     * encountered which matches the specified name. You can also pass null as
     * the name, in which case the handler will be called for any unmatched
     * start tag.
     *
     * Examples:
     * --------------
     * // Call this function whenever a <podcast> start tag is encountered
     * onStartTag["podcast"] = (ElementParser xml)
     * {
     *     // Your code here
     *     //
     *     // This is a a closure, so code here may reference
     *     // variables which are outside of this scope
     * };
     *
     * // call myEpisodeStartHandler (defined elsewhere) whenever an <episode>
     * // start tag is encountered
     * onStartTag["episode"] = &myEpisodeStartHandler;
     *
     * // call delegate dg for all other start tags
     * onStartTag[null] = dg;
     * --------------
     *
     * This library will supply your function with a new instance of
     * ElementHandler, which may be used to parse inside the element whose
     * start tag was just found, or to identify the tag attributes of the
     * element, etc.
     *
     * Note that your function will be called for both start tags and empty
     * tags. That is, we make no distinction between &lt;br&gt;&lt;/br&gt;
     * and &lt;br/&gt;.
     */
    ParserHandler[string] onStartTag;

    /**
     * Register a handler which will be called whenever an end tag is
     * encountered which matches the specified name. You can also pass null as
     * the name, in which case the handler will be called for any unmatched
     * end tag.
     *
     * Examples:
     * --------------
     * // Call this function whenever a </podcast> end tag is encountered
     * onEndTag["podcast"] = (in Element e)
     * {
     *     // Your code here
     *     //
     *     // This is a a closure, so code here may reference
     *     // variables which are outside of this scope
     * };
     *
     * // call myEpisodeEndHandler (defined elsewhere) whenever an </episode>
     * // end tag is encountered
     * onEndTag["episode"] = &myEpisodeEndHandler;
     *
     * // call delegate dg for all other end tags
     * onEndTag[null] = dg;
     * --------------
     *
     * Note that your function will be called for both start tags and empty
     * tags. That is, we make no distinction between &lt;br&gt;&lt;/br&gt;
     * and &lt;br/&gt;.
     */
    ElementHandler[string] onEndTag;

    protected this()
    {
        elementStart = *s;
		version(GC_STATS)
			gcStatsSum.inc();

    }

    /**
     * Register a handler which will be called whenever text is encountered.
     *
     * Examples:
     * --------------
     * // Call this function whenever text is encountered
     * onText = (string s)
     * {
     *     // Your code here
     *
     *     // The passed parameter s will have been decoded by the time you see
     *     // it, and so may contain any character.
     *     //
     *     // This is a a closure, so code here may reference
     *     // variables which are outside of this scope
     * };
     * --------------
     */
    @property void onText(Handler handler) { textHandler = handler; }

    /**
     * Register an alternative handler which will be called whenever text
     * is encountered. This differs from onText in that onText will decode
     * the text, whereas onTextRaw will not. This allows you to make design
     * choices, since onText will be more accurate, but slower, while
     * onTextRaw will be faster, but less accurate. Of course, you can
     * still call decode() within your handler, if you want, but you'd
     * probably want to use onTextRaw only in circumstances where you
     * know that decoding is unnecessary.
     *
     * Examples:
     * --------------
     * // Call this function whenever text is encountered
     * onText = (string s)
     * {
     *     // Your code here
     *
     *     // The passed parameter s will NOT have been decoded.
     *     //
     *     // This is a a closure, so code here may reference
     *     // variables which are outside of this scope
     * };
     * --------------
     */
    void onTextRaw(Handler handler) { rawTextHandler = handler; }

    /**
     * Register a handler which will be called whenever a character data
     * segment is encountered.
     *
     * Examples:
     * --------------
     * // Call this function whenever a CData section is encountered
     * onCData = (string s)
     * {
     *     // Your code here
     *
     *     // The passed parameter s does not include the opening <![CDATA[
     *     // nor closing ]]>
     *     //
     *     // This is a a closure, so code here may reference
     *     // variables which are outside of this scope
     * };
     * --------------
     */
    @property void onCData(Handler handler) { cdataHandler = handler; }

    /**
     * Register a handler which will be called whenever a comment is
     * encountered.
     *
     * Examples:
     * --------------
     * // Call this function whenever a comment is encountered
     * onComment = (string s)
     * {
     *     // Your code here
     *
     *     // The passed parameter s does not include the opening <!-- nor
     *     // closing -->
     *     //
     *     // This is a a closure, so code here may reference
     *     // variables which are outside of this scope
     * };
     * --------------
     */
    @property void onComment(Handler handler) { commentHandler = handler; }

    /**
     * Register a handler which will be called whenever a processing
     * instruction is encountered.
     *
     * Examples:
     * --------------
     * // Call this function whenever a processing instruction is encountered
     * onPI = (string s)
     * {
     *     // Your code here
     *
     *     // The passed parameter s does not include the opening <? nor
     *     // closing ?>
     *     //
     *     // This is a a closure, so code here may reference
     *     // variables which are outside of this scope
     * };
     * --------------
     */
    @property void onPI(Handler handler) { piHandler = handler; }

    /**
     * Register a handler which will be called whenever an XML instruction is
     * encountered.
     *
     * Examples:
     * --------------
     * // Call this function whenever an XML instruction is encountered
     * // (Note: XML instructions may only occur preceding the root tag of a
     * // document).
     * onPI = (string s)
     * {
     *     // Your code here
     *
     *     // The passed parameter s does not include the opening <! nor
     *     // closing >
     *     //
     *     // This is a a closure, so code here may reference
     *     // variables which are outside of this scope
     * };
     * --------------
     */
    @property void onXI(Handler handler) { xiHandler = handler; }

    /**
     * Parse an XML element.
     *
     * Parsing will continue until the end of the current element. Any items
     * encountered for which a handler has been registered will invoke that
     * handler.
     *
     * Throws: various kinds of XMLException
     */
    void parse()
    {
        string t;
		Appender!(Tag[])  tagStack;
		scope(exit)
		{
			auto tags = tagStack.data;
			auto slen = tags.length;
			while (slen > 0)
			{
				slen -= 1;
				auto oldtag = tags[slen];
				tagStack.shrinkTo(slen);
				destroy(oldtag);
			}
		}

        while(s.length != 0)
        {
            if (startsWith(*s,"<!--"))
            {
                chop(*s,4);
                t = chop(*s,indexOf(*s,"-->"));
                if (commentHandler.funcptr !is null) commentHandler(t);
                chop(*s,3);
            }
            else if (startsWith(*s,"<![CDATA["))
            {
                chop(*s,9);
                t = chop(*s,indexOf(*s,"]]>"));
                if (cdataHandler.funcptr !is null) cdataHandler(t);
                chop(*s,3);
            }
            else if (startsWith(*s,"<!"))
            {
                chop(*s,2);
                t = chop(*s,indexOf(*s,">"));
                if (xiHandler.funcptr !is null) xiHandler(t);
                chop(*s,1);
            }
            else if (startsWith(*s,"<?"))
            {
                chop(*s,2);
                t = chop(*s,indexOf(*s,"?>"));
                if (piHandler.funcptr !is null) piHandler(t);
                chop(*s,2);
            }
            else if (startsWith(*s,"<"))
            {
				TagData tdata =  TagData(*s,true); // gets all attributes
				
				// why would it be null? - for DocumentParser
                if (tag_ is null)
				{
					tag_ = new Tag(tdata);
                    return; // Return to constructor of derived class
				}
				
				if (tdata.isStart)
				{
					auto handler = tdata.name in onStartTag;
					if (handler is null)
					{
						 handler = null in onStartTag;
					}
					auto unknown = new Tag(tdata);
					tagStack ~= unknown; // must remember this
					if (handler !is null)
					{
						auto parser = new ElementParser(this,tdata);
						(*handler)(parser);
						parser.explode();
						destroy(parser);
					}
				}
                else if (tdata.isEnd)
                {
					Tag eTag;
					auto stack = tagStack.data;
					auto slen = stack.length;

					if (slen > 0)
					{
						slen--;
						eTag = stack[slen];
						tagStack.shrinkTo(slen);
					}
					else
						eTag = tag_;
					auto handler2 = tdata.name in onEndTag;
					if (handler2 is null)
					{
						handler2 = null in onEndTag;
					}
					if (handler2 !is null)
					{
						string text;
						
						immutable(char)* p = eTag.tagString.ptr
							+ eTag.tagString.length;
						immutable(char)* q = tdata.tagString.ptr;
						text = decode(p[0..(q-p)], DecodeMode.LOOSE);

						auto element = new Element(eTag);
						if (text.length != 0) element ~= new Text(text);
						(*handler2)(element);
						element.explode();
						
					}
					if (eTag !is tag_)
						destroy(eTag);
                    if (tdata.name == tag_.name)
					{
						return;
					}
                }
                else if (tdata.isEmpty)
                {
                    string s2;
                    auto handler1 = tdata.name in onStartTag;
                    if (handler1 is null)
					{
						 handler1 = null in onStartTag;
					}
                    if (handler1 !is null) 
					{
						auto parser = new ElementParser(tdata,&s2);
						(*handler1)(parser);
						parser.explode();
						destroy(parser);
                    }
                    auto handler2 = tdata.name in onEndTag;
					if (handler2 is null)
					{
						handler2 = null in onEndTag;
					}
					if (handler2 !is null)
					{   // Handle the pretend end tag
						auto element = new Element(tdata);
						(*handler2)(element);
						element.explode();
					}	
                }
            }
            else
            {
                t = chop(*s,indexOf(*s,"<"));
                if (rawTextHandler.funcptr !is null)
                    rawTextHandler(t);
                else if (textHandler.funcptr !is null)
                    textHandler(decode(t,DecodeMode.LOOSE));
            }
        }
    }

    /**
     * Returns that part of the element which has already been parsed
     */
    override string toString() const
    {
        assert(elementStart.length >= s.length);
        return elementStart[0 .. elementStart.length - s.length];
    }

}


 
    // Helper functions 
bool foundLiteral(string literal, ref string s)
{
	if (s.startsWith(literal))
	{
		s = s[literal.length..$];
		return true;
	}
	return false;
}

void checkLiteral(string literal,ref string s)
{
    if (!s.startsWith(literal)) 
		failCheck(s,"Expected literal \""~literal~"\"");
	s = s[literal.length..$]; 
}

void checkEnd(string end,ref string s)
{
    auto n = s.indexOf(end);
    if (n == -1) throw new Err(s,"Unable to find terminating \""~end~"\"");
    s = s[n..$];
    checkLiteral(end,s);
} 



/**
 * Check an entire XML document for well-formedness
 *
 * Params:
 *      s = the document to be checked, passed as a string
 *
 * Throws: CheckException if the document is not well formed
 *
 * CheckException's toString() method will yield the complete hierarchy of
 * parse failure (the XML equivalent of a stack trace), giving the line and
 * column number of every failure at every level.
 */
void check(string s)
{
	XmlValidate v = new XmlValidate();
	scope(exit)
		destroy(v);
	auto entire = s; // remember entire
    try
    {
		
		v.fullCheck(s);
		
        if (s.length != 0) throw new Err(s,"Junk found after document");
    }
    catch(Err e)
    {
        e.complete(entire);
        throw e;
    }
}

unittest
{
  version (none) // WHY ARE WE NOT RUNNING THIS UNIT TEST?
  {
    try
    {
        check(q"[<?xml version="1.0"?>
        <catalog>
           <book id="bk101">
              <author>Gambardella, Matthew</author>
              <title>XML Developer's Guide</title>
              <genre>Computer</genre>
              <price>44.95</price>
              <publish_date>2000-10-01</publish_date>
              <description>An in-depth look at creating applications
              with XML.</description>
           </book>
           <book id="bk102">
              <author>Ralls, Kim</author>
              <title>Midnight Rain</title>
              <genre>Fantasy</genres>
              <price>5.95</price>
              <publish_date>2000-12-16</publish_date>
              <description>A former architect battles corporate zombies,
              an evil sorceress, and her own childhood to become queen
              of the world.</description>
           </book>
           <book id="bk103">
              <author>Corets, Eva</author>
              <title>Maeve Ascendant</title>
              <genre>Fantasy</genre>
              <price>5.95</price>
              <publish_date>2000-11-17</publish_date>
              <description>After the collapse of a nanotechnology
              society in England, the young survivors lay the
              foundation for a new society.</description>
           </book>
        </catalog>
        ]");
    assert(false);
    }
    catch(CheckException e)
    {
        int n = e.toString().indexOf("end tag name \"genres\" differs"~
            " from start tag name \"genre\"");
        assert(n != -1);
    }
  }
}

unittest
{
    string s = q"EOS
<?xml version="1.0"?>
<set>
    <one>A</one>
    <!-- comment -->
    <two>B</two>
</set>
EOS";
    try
    {
        check(s);
    }
    catch (CheckException e)
    {
        assert(0, e.toString());
    }
}

unittest
{
    string s = q"EOS
<?xml version="1.0" encoding="utf-8"?> <Tests>
    <Test thing="What &amp; Up">What &amp; Up Second</Test>
</Tests>
EOS";
    auto xml = new DocumentParser(s);

    xml.onStartTag["Test"] = (ElementParser xml) {
        assert(xml.tag.attr["thing"] == "What & Up");
    };

    xml.onEndTag["Test"] = (in Element e) {
        assert(e.text() == "What & Up Second");
    };
    xml.parse();
}

unittest
{
    string s = `<tag attr="&quot;value&gt;" />`;
    auto doc = new Document(s);
    assert(doc.toString() == s);
}

/** The base class for exceptions thrown by this module */
class XMLException : Exception { this(string msg) { super(msg); } }

// Other exceptions

/// Thrown during Comment constructor
class CommentException : XMLException
{ private this(string msg) { super(msg); } }

/// Thrown during CData constructor
class CDataException : XMLException
{ private this(string msg) { super(msg); } }

/// Thrown during XMLInstruction constructor
class XIException : XMLException
{ private this(string msg) { super(msg); } }

/// Thrown during ProcessingInstruction constructor
class PIException : XMLException
{ private this(string msg) { super(msg); } }

/// Thrown during Text constructor
class TextException : XMLException
{ private this(string msg) { super(msg); } }

/// Thrown during decode()
class DecodeException : XMLException
{ private this(string msg) { super(msg); } }

/// Thrown if comparing with wrong type
class InvalidTypeException : XMLException
{ private this(string msg) { super(msg); } }

/// Thrown when parsing for Tags
class TagException : XMLException
{ private this(string msg) { super(msg); } }

/**
 * Thrown during check()
 */
class CheckException : XMLException
{
    CheckException err; /// Parent in hierarchy
    private string tail;
    /**
     * Name of production rule which failed to parse,
     * or specific error message
     */
    string msg;
    size_t line = 0; /// Line number at which parse failure occurred
    size_t column = 0; /// Column number at which parse failure occurred

    private this(string tail,string msg,Err err=null)
    {
        super(null);
        this.tail = tail;
        this.msg = msg;
        this.err = err;
    }

    private void complete(string entire)
    {
        string head = entire[0..$-tail.length];
        ptrdiff_t n = head.lastIndexOf('\n') + 1;
        line = head.count("\n") + 1;
        dstring t;
        transcode(head[n..$],t);
        column = t.length + 1;
        if (err !is null) err.complete(entire);
    }

    override string toString() const
    {
        string s;
        if (line != 0) s = format("Line %d, column %d: ",line,column);
        s ~= msg;
        s ~= '\n';
        if (err !is null) s = err.toString() ~ s;
        return s;
    }
}

private alias Err = CheckException;

// Private helper functions

private
{
    T toType(T)(Object o)
    {
        T t = cast(T)(o);
        if (t is null)
        {
            throw new InvalidTypeException("Attempt to compare a "
                ~ T.stringof ~ " with an instance of another type");
        }
        return t;
    }

    string chop(ref string s, size_t n)
    {
        if (n == -1) n = s.length;
        string t = s[0..n];
        s = s[n..$];
        return t;
    }

    bool optc(ref string s, char c)
    {
        bool b = s.length != 0 && s[0] == c;
        if (b) s = s[1..$];
        return b;
    }

    void reqc(ref string s, char c)
    {
        if (s.length == 0 || s[0] != c) throw new TagException("");
        s = s[1..$];
    }

    size_t hash(string s,size_t h=0) @trusted nothrow
    {
        return typeid(s).getHash(&s) + h;
    }

    // Definitions from the XML specification
    immutable CharTable=[0x9,0x9,0xA,0xA,0xD,0xD,0x20,0xD7FF,0xE000,0xFFFD,
        0x10000,0x10FFFF];
    immutable BaseCharTable=[0x0041,0x005A,0x0061,0x007A,0x00C0,0x00D6,0x00D8,
        0x00F6,0x00F8,0x00FF,0x0100,0x0131,0x0134,0x013E,0x0141,0x0148,0x014A,
        0x017E,0x0180,0x01C3,0x01CD,0x01F0,0x01F4,0x01F5,0x01FA,0x0217,0x0250,
        0x02A8,0x02BB,0x02C1,0x0386,0x0386,0x0388,0x038A,0x038C,0x038C,0x038E,
        0x03A1,0x03A3,0x03CE,0x03D0,0x03D6,0x03DA,0x03DA,0x03DC,0x03DC,0x03DE,
        0x03DE,0x03E0,0x03E0,0x03E2,0x03F3,0x0401,0x040C,0x040E,0x044F,0x0451,
        0x045C,0x045E,0x0481,0x0490,0x04C4,0x04C7,0x04C8,0x04CB,0x04CC,0x04D0,
        0x04EB,0x04EE,0x04F5,0x04F8,0x04F9,0x0531,0x0556,0x0559,0x0559,0x0561,
        0x0586,0x05D0,0x05EA,0x05F0,0x05F2,0x0621,0x063A,0x0641,0x064A,0x0671,
        0x06B7,0x06BA,0x06BE,0x06C0,0x06CE,0x06D0,0x06D3,0x06D5,0x06D5,0x06E5,
        0x06E6,0x0905,0x0939,0x093D,0x093D,0x0958,0x0961,0x0985,0x098C,0x098F,
        0x0990,0x0993,0x09A8,0x09AA,0x09B0,0x09B2,0x09B2,0x09B6,0x09B9,0x09DC,
        0x09DD,0x09DF,0x09E1,0x09F0,0x09F1,0x0A05,0x0A0A,0x0A0F,0x0A10,0x0A13,
        0x0A28,0x0A2A,0x0A30,0x0A32,0x0A33,0x0A35,0x0A36,0x0A38,0x0A39,0x0A59,
        0x0A5C,0x0A5E,0x0A5E,0x0A72,0x0A74,0x0A85,0x0A8B,0x0A8D,0x0A8D,0x0A8F,
        0x0A91,0x0A93,0x0AA8,0x0AAA,0x0AB0,0x0AB2,0x0AB3,0x0AB5,0x0AB9,0x0ABD,
        0x0ABD,0x0AE0,0x0AE0,0x0B05,0x0B0C,0x0B0F,0x0B10,0x0B13,0x0B28,0x0B2A,
        0x0B30,0x0B32,0x0B33,0x0B36,0x0B39,0x0B3D,0x0B3D,0x0B5C,0x0B5D,0x0B5F,
        0x0B61,0x0B85,0x0B8A,0x0B8E,0x0B90,0x0B92,0x0B95,0x0B99,0x0B9A,0x0B9C,
        0x0B9C,0x0B9E,0x0B9F,0x0BA3,0x0BA4,0x0BA8,0x0BAA,0x0BAE,0x0BB5,0x0BB7,
        0x0BB9,0x0C05,0x0C0C,0x0C0E,0x0C10,0x0C12,0x0C28,0x0C2A,0x0C33,0x0C35,
        0x0C39,0x0C60,0x0C61,0x0C85,0x0C8C,0x0C8E,0x0C90,0x0C92,0x0CA8,0x0CAA,
        0x0CB3,0x0CB5,0x0CB9,0x0CDE,0x0CDE,0x0CE0,0x0CE1,0x0D05,0x0D0C,0x0D0E,
        0x0D10,0x0D12,0x0D28,0x0D2A,0x0D39,0x0D60,0x0D61,0x0E01,0x0E2E,0x0E30,
        0x0E30,0x0E32,0x0E33,0x0E40,0x0E45,0x0E81,0x0E82,0x0E84,0x0E84,0x0E87,
        0x0E88,0x0E8A,0x0E8A,0x0E8D,0x0E8D,0x0E94,0x0E97,0x0E99,0x0E9F,0x0EA1,
        0x0EA3,0x0EA5,0x0EA5,0x0EA7,0x0EA7,0x0EAA,0x0EAB,0x0EAD,0x0EAE,0x0EB0,
        0x0EB0,0x0EB2,0x0EB3,0x0EBD,0x0EBD,0x0EC0,0x0EC4,0x0F40,0x0F47,0x0F49,
        0x0F69,0x10A0,0x10C5,0x10D0,0x10F6,0x1100,0x1100,0x1102,0x1103,0x1105,
        0x1107,0x1109,0x1109,0x110B,0x110C,0x110E,0x1112,0x113C,0x113C,0x113E,
        0x113E,0x1140,0x1140,0x114C,0x114C,0x114E,0x114E,0x1150,0x1150,0x1154,
        0x1155,0x1159,0x1159,0x115F,0x1161,0x1163,0x1163,0x1165,0x1165,0x1167,
        0x1167,0x1169,0x1169,0x116D,0x116E,0x1172,0x1173,0x1175,0x1175,0x119E,
        0x119E,0x11A8,0x11A8,0x11AB,0x11AB,0x11AE,0x11AF,0x11B7,0x11B8,0x11BA,
        0x11BA,0x11BC,0x11C2,0x11EB,0x11EB,0x11F0,0x11F0,0x11F9,0x11F9,0x1E00,
        0x1E9B,0x1EA0,0x1EF9,0x1F00,0x1F15,0x1F18,0x1F1D,0x1F20,0x1F45,0x1F48,
        0x1F4D,0x1F50,0x1F57,0x1F59,0x1F59,0x1F5B,0x1F5B,0x1F5D,0x1F5D,0x1F5F,
        0x1F7D,0x1F80,0x1FB4,0x1FB6,0x1FBC,0x1FBE,0x1FBE,0x1FC2,0x1FC4,0x1FC6,
        0x1FCC,0x1FD0,0x1FD3,0x1FD6,0x1FDB,0x1FE0,0x1FEC,0x1FF2,0x1FF4,0x1FF6,
        0x1FFC,0x2126,0x2126,0x212A,0x212B,0x212E,0x212E,0x2180,0x2182,0x3041,
        0x3094,0x30A1,0x30FA,0x3105,0x312C,0xAC00,0xD7A3];
    immutable IdeographicTable=[0x3007,0x3007,0x3021,0x3029,0x4E00,0x9FA5];
    immutable CombiningCharTable=[0x0300,0x0345,0x0360,0x0361,0x0483,0x0486,
        0x0591,0x05A1,0x05A3,0x05B9,0x05BB,0x05BD,0x05BF,0x05BF,0x05C1,0x05C2,
        0x05C4,0x05C4,0x064B,0x0652,0x0670,0x0670,0x06D6,0x06DC,0x06DD,0x06DF,
        0x06E0,0x06E4,0x06E7,0x06E8,0x06EA,0x06ED,0x0901,0x0903,0x093C,0x093C,
        0x093E,0x094C,0x094D,0x094D,0x0951,0x0954,0x0962,0x0963,0x0981,0x0983,
        0x09BC,0x09BC,0x09BE,0x09BE,0x09BF,0x09BF,0x09C0,0x09C4,0x09C7,0x09C8,
        0x09CB,0x09CD,0x09D7,0x09D7,0x09E2,0x09E3,0x0A02,0x0A02,0x0A3C,0x0A3C,
        0x0A3E,0x0A3E,0x0A3F,0x0A3F,0x0A40,0x0A42,0x0A47,0x0A48,0x0A4B,0x0A4D,
        0x0A70,0x0A71,0x0A81,0x0A83,0x0ABC,0x0ABC,0x0ABE,0x0AC5,0x0AC7,0x0AC9,
        0x0ACB,0x0ACD,0x0B01,0x0B03,0x0B3C,0x0B3C,0x0B3E,0x0B43,0x0B47,0x0B48,
        0x0B4B,0x0B4D,0x0B56,0x0B57,0x0B82,0x0B83,0x0BBE,0x0BC2,0x0BC6,0x0BC8,
        0x0BCA,0x0BCD,0x0BD7,0x0BD7,0x0C01,0x0C03,0x0C3E,0x0C44,0x0C46,0x0C48,
        0x0C4A,0x0C4D,0x0C55,0x0C56,0x0C82,0x0C83,0x0CBE,0x0CC4,0x0CC6,0x0CC8,
        0x0CCA,0x0CCD,0x0CD5,0x0CD6,0x0D02,0x0D03,0x0D3E,0x0D43,0x0D46,0x0D48,
        0x0D4A,0x0D4D,0x0D57,0x0D57,0x0E31,0x0E31,0x0E34,0x0E3A,0x0E47,0x0E4E,
        0x0EB1,0x0EB1,0x0EB4,0x0EB9,0x0EBB,0x0EBC,0x0EC8,0x0ECD,0x0F18,0x0F19,
        0x0F35,0x0F35,0x0F37,0x0F37,0x0F39,0x0F39,0x0F3E,0x0F3E,0x0F3F,0x0F3F,
        0x0F71,0x0F84,0x0F86,0x0F8B,0x0F90,0x0F95,0x0F97,0x0F97,0x0F99,0x0FAD,
        0x0FB1,0x0FB7,0x0FB9,0x0FB9,0x20D0,0x20DC,0x20E1,0x20E1,0x302A,0x302F,
        0x3099,0x3099,0x309A,0x309A];
    immutable DigitTable=[0x0030,0x0039,0x0660,0x0669,0x06F0,0x06F9,0x0966,
        0x096F,0x09E6,0x09EF,0x0A66,0x0A6F,0x0AE6,0x0AEF,0x0B66,0x0B6F,0x0BE7,
        0x0BEF,0x0C66,0x0C6F,0x0CE6,0x0CEF,0x0D66,0x0D6F,0x0E50,0x0E59,0x0ED0,
        0x0ED9,0x0F20,0x0F29];
    immutable ExtenderTable=[0x00B7,0x00B7,0x02D0,0x02D0,0x02D1,0x02D1,0x0387,
        0x0387,0x0640,0x0640,0x0E46,0x0E46,0x0EC6,0x0EC6,0x3005,0x3005,0x3031,
        0x3035,0x309D,0x309E,0x30FC,0x30FE];

    bool lookup(const(int)[] table, int c)
    {
        while (table.length != 0)
        {
            auto m = (table.length >> 1) & ~1;
            if (c < table[m])
            {
                table = table[0..m];
            }
            else if (c > table[m+1])
            {
                table = table[m+2..$];
            }
            else return true;
        }
        return false;
    }

    string startOf(string s)
    {
        string r;
        foreach(char c;s)
        {
            r ~= (c < 0x20 || c > 0x7F) ? '.' : c;
            if (r.length >= 40) { r ~= "___"; break; }
        }
        return r;
    }

    void exit(string s=null)
    {
        throw new XMLException(s);
    }
}

/// The check code and mixins are pretty amazing, but the use of exceptions is a drag on performance
/// attempt to provide same style but with good old stack and return codes.

struct CheckState {
	string		name;	
	string		ctx;

	this(string lname, string save)
	{
		name = lname;
		ctx = save;
	}

	bool same(ref string s) const
	{
		return ctx.ptr == s.ptr;
	}
}

enum XmlValid {
	VALID,
	INVALID,
	FAIL,
}

enum Requirement {
	ZERO,
	ONE,
	MANY,
	OPTION = 4,
	NEED = 8,
}





class XmlValidate {
	Appender!(CheckState[])			stack_;  // keep track of temporary slice alterations
	Appender!(CheckException[])		errors_;
	XmlValid	status;
	Requirement	require;
	
	CheckState getContext()
	{
		auto sdata = stack_.data;
		auto slen = sdata.length;
		if (slen > 0)
		{	
			slen--;
			return sdata[slen];
		}
		// TODO: else big fail?
		assert(0);
	}
	CheckState pushContext(string lname, string s)
	{
		auto result = CheckState(lname,s);
		stack_.put(result);
		return result;
	}
	void popContext()
	{
		auto sdata = stack_.data;
		auto slen = sdata.length;
		if (slen > 0)
		{	
			slen--;
			stack_.shrinkTo(slen);
			return;
		}
		// TODO: else big fail?
		assert(0);
	}

	void failed(Err e)
	{
		auto level = getContext();
		throw new Err(level.ctx,level.name,e);
	}
	void failed()
	{
		auto level = getContext();
		throw  new Err(level.ctx,level.name, null);
	}
	void failed(string msg)
	{
		auto level = getContext();
		throw new Err(level.ctx,msg, null);
	}

	void failSpace()
	{
		failed("A space character is needed");
	}
	void updateStatus(XmlValid v)
	{
		if (cast(int) v > cast(int) status)
			status = v;
	}
	// failure throws FAIL
	void checkLiteral(string literal,ref string s)
    {
        auto level = pushContext("Literal",s);
		scope(exit)
			popContext();
        if (!s.startsWith(literal)) 
			failed("Expected literal \""~literal~"\"");
		s = s[literal.length..$];
    }
	uint spaceCount(ref string s)
	{
		auto start = s;
		munch(s,"\u0020\u0009\u000A\u000D");
		return (s.ptr - start.ptr);
	}

    bool checkSpace(ref string s, Requirement req) // rule 3
    {
        pushContext("Whitespace",s);
		scope(exit)
			popContext();
		auto level = getContext();
        munch(s,"\u0020\u0009\u000A\u000D");
		auto ct = s.ptr - level.ctx.ptr;
		if (ct < 1 && req != Requirement.OPTION)
			failSpace();
		return (ct > 0);
    }
	void pair(alias f,alias g)(ref string s)
    {
        if (f(s,Requirement.OPTION))
		{
			g(s,Requirement.NEED);
		}
    }
	void quoted(alias f)(ref string s, Requirement req)
    {
		auto quoteChar = "\'";

		if (foundLiteral(quoteChar,s))
		{
			f(s,req);
		}
		else {
			quoteChar = "\"";
			if (foundLiteral(quoteChar,s))
			{
				f(s,req);
			}
			else {
				failed();
			}
		}
		checkLiteral(quoteChar,s);
    }

	void need(alias f)(ref string s)
	{
		return f(s,Requirement.NEED);
	}

    void maybe(alias f)(ref string s)
    {
		f(s,Requirement.OPTION);
    }
    void many(alias f)(ref string s)
    {
		int ct = 0;
        do
        {
            ct = f(s,Requirement.MANY);
        }
		while (ct > 0);
    }

    void checkEq(ref string s) // rule 25
    {
        pushContext("Eq",s);
        scope(exit)
			popContext();
		maybe!(checkSpace)(s);
        checkLiteral("=",s);
        maybe!(checkSpace)(s);
    }

    void checkEncodingDecl(ref string s, Requirement req) // rule 80
    {
        auto level = pushContext("EncodingDecl",s);
		scope(exit)
			popContext();

        auto ct = spaceCount(s);
        if (foundLiteral("encoding",s))
		{	
			if (ct < 1)
				failSpace();
			checkEq(s);
			quoted!(checkEncName)(s,req);
		}
		else {
			s = level.ctx;
		}
    }

    void checkEncName(ref string s, Requirement req) // rule 81
    {
        auto level = pushContext("EncName",s);

        munch(s,"a-zA-Z");
        if (level.same(s)) failed();
        munch(s,"a-zA-Z0-9_.-");
    }

	void checkXMLDecl(ref string s, Requirement req)
	{
		auto level = pushContext("XMLDecl",s);
		scope(exit)
			popContext();
		if (foundLiteral("<?xml",s)) 
		{
			// xml dec is not compulsory, once in , better be good
			checkVersionInfo(s,Requirement.NEED);
			maybe!(checkEncodingDecl)(s);
			maybe!(checkSDDecl)(s);
			maybe!(checkSpace)(s);
			checkLiteral("?>",s);
		}
	}
    void checkVersionNum(ref string s, Requirement req) // rule 26
    {
        auto level = pushContext("VersionNum",s);
		scope(exit)
			popContext();
        munch(s,"a-zA-Z0-9_.:-"); // not very specific
        if (level.same(s)) 
			failed();
    }
	void checkYesNo(ref string s, Requirement req)
	{
		if (foundLiteral("yes",s)  || foundLiteral("no",s))
		{
			return;
		}
		else {
			failed("yes or no attribute value required");
		}
	}

    void checkSDDecl(ref string s, Requirement req) // rule 32
    {
        auto level = pushContext("SDDecl",s);
		scope(exit)
			popContext();

		auto ct = spaceCount(s);
        if (foundLiteral("standalone",s))
		{
			if (ct < 1)
				failSpace();
            checkEq(s);
			quoted!(checkYesNo)(s,Requirement.NEED);
		}
		else
			s = level.ctx;
    }
    void checkVersionInfo(ref string s, Requirement req) // rule 24
    {
        auto level = pushContext("VersionInfo",s);
		scope(exit)
			popContext();

		auto ct = spaceCount(s);
        if (foundLiteral("version",s))
		{
			if (ct < 1)
				failSpace();
			checkEq(s);
			quoted!(this.checkVersionNum)(s,req);
		}
		else {
			if (req == Requirement.NEED)
			{
				failed(level.name);
			}
			s = level.ctx;
		}
    }
	void checkProlog(ref string s, Requirement req) // rule 22
    {
        auto level = pushContext("Prolog",s);
		scope(exit)
			popContext();
        maybe!(checkXMLDecl)(s);
        many!(checkMisc)(s);
            //maybe!(seq!(checkDocTypeDecl,many!(checkMisc)))(s);
    }

	// should only throw exception if not well formed
	void checkDocument(ref string s) // rule 1
    {
        auto level=pushContext("Document",s);
		scope(exit)
			popContext();
		checkProlog(s,Requirement.OPTION);
		checkElement(s);
		many!(checkMisc)(s);
    }
    void checkComment(ref string s,Requirement req) // rule 15
    {
        auto level = pushContext("Comment",s);
		scope(exit)
			popContext();
        if (foundLiteral("<!--",s))
		{
			ptrdiff_t n = s.indexOf("--");
			if (n == -1) 
				failed("unterminated comment");
			s = s[n..$];
			checkLiteral("-->",s);
		}
    }
    void checkEnd(string end,ref string s)
    {
        auto n = s.indexOf(end);
        if (n == -1)
			failed(format("Unable to find terminating \"%s\"", end));
        s = s[n..$];
        checkLiteral(end,s);
    }
    void checkPI(ref string s,Requirement req) // rule 16
    {
        auto level = pushContext("PI",s);
		scope(exit)
			popContext();
        if (foundLiteral("<?",s))
		{
			checkEnd("?>",s);
        }
    }
    int checkMisc(ref string s, Requirement req) // rule 27
    {
        auto level = pushContext("Misc",s);
		scope(exit)
			popContext();
		auto ct = spaceCount(s); 
		if (s.startsWith("<!--")) 
		{ 
			need!(checkComment)(s); 
			ct++;
		}
		else if (s.startsWith("<?"))   
		{ 
			need!(checkPI)(s);
			ct++;
		}
		return ct;
    }
	void checkElement(ref string s) // rule 39
    {
        auto level = pushContext("Element",s);
		scope(exit)
			popContext();
        string sname,ename,t;
		checkTag(s,t,sname); 

        if (t == "STag")
        {
            checkContent(s);
            t = s;
            checkETag(s,ename);
            if (sname != ename)
            {
                s = t;
                failed(format("end tag name '%s' differs from start tag name '%s'", ename,sname));
            }
        }
    }

    bool checkName(ref string s, out string name) // rule 5
    {
        if (s.length == 0) 
			return false;
        int n;
        foreach(int i,dchar c;s)
        {
            if (c == '_' || c == ':' || isLetter(c)) continue;
            if (i == 0) 
				return false; // not a beginning of name
            if (c == '-' || c == '.' || isDigit(c)
                || isCombiningChar(c) || isExtender(c)) continue;
            n = i;
            break;
        }
        name = s[0..n];
        s = s[n..$];
		return true;
    }
	// rules 40 and 44
    void checkTag(ref string s, out string type, out string name)
    {
        auto level = pushContext("Tag",s);
		scope(exit)
			popContext();
        type = "STag";
        checkLiteral("<",s);
        checkName(s,name);

        many!(checkAttribute)(s);
        maybe!(checkSpace)(s);
        if (s.length != 0 && s[0] == '/')
        {
            s = s[1..$];
            type = "ETag";
        }
        checkLiteral(">",s);
    }
	void checkReference(ref string s) // rule 67
    {
        auto level = pushContext("Reference",s);
		scope(exit)
			popContext();
		dchar c;
		if (s.startsWith("&#"))
			checkCharRef(s,c);
		else 
			checkEntityRef(s);
    }
	int checkAttribute(ref string s, Requirement req) // rule 41
    {
        auto level = pushContext("Attribute",s);
		scope(exit)
			popContext();
        string name;
		auto ct = spaceCount(s);
		if (checkName(s,name))
		{
			if (ct < 1)
				failSpace();
			checkEq(s);
			checkAttValue(s);
		}
		return ct;
	}
    void checkEntityRef(ref string s) // rule 68
    {
		auto level = pushContext("EntityRef",s);
		scope(exit)
			popContext();
        string name;
        checkLiteral("&",s);
        checkName(s, name);
        checkLiteral(";",s);
    }


    void checkETag(ref string s, out string name) // rule 42
    {
        auto level = pushContext("ETag",s);
		scope(exit)
			popContext();
        checkLiteral("</",s);
        checkName(s,name);
        spaceCount(s);
        checkLiteral(">",s);
    }
	void checkContent(ref string s) // rule 43
    {
		auto level = pushContext("Content",s);
		scope(exit)
			popContext();
        while (s.length != 0)
        {
			if (s.startsWith("&"))			
			{ 
				checkReference(s); 
			}
            else if (s.startsWith("<!--"))     
			{ 
				checkComment(s,Requirement.NEED); 
			}
            else if (s.startsWith("<?"))      
			{ 
				checkPI(s,Requirement.NEED); 
			}
            else if (s.startsWith(cdata)) 
			{ 
				checkCDSect(s); 
			}
            else if (s.startsWith("</"))       
			{ 
				break; 
			}
            else if (s.startsWith("<"))        
			{ 
				checkElement(s); 
			}
            else 
			{ 
				checkCharData(s); 
			}
        }
    }
    void checkCDSect(ref string s) // rule 18
    {
        auto level = pushContext("CDSect",s);
		scope(exit)
			popContext();

        checkLiteral(cdata,s);
        checkEnd("]]>",s);
    }
    void checkAttValue(ref string s) // rule 10
    {
        auto level = pushContext("AttValue",s);
		scope(exit)
			popContext();
        if (s.length == 0) 
			failed();
        char c = s[0];
        if (c != '\u0022' && c != '\u0027')
            failed("attribute value requires quotes");
        s = s[1..$];
        for(;;)
        {
            munch(s,"^<&"~c);
            if (s.length == 0) failed("unterminated attribute value");
            if (s[0] == '<') failed("< found in attribute value");
            if (s[0] == c) break;
            checkReference(s);
        }
        s = s[1..$];
    }
    void checkChars(ref string s) // rule 2
    {
        // TO DO - Fix std.utf stride and decode functions, then use those
        // instead

        auto level = pushContext("Chars",s);
		scope(exit)
			popContext();

        dchar c;
        int n = -1;
        foreach(int i,dchar d; s)
        {
            if (!isChar(d))
            {
                c = d;
                n = i;
                break;
            }
        }
        if (n != -1)
        {
            s = s[n..$];
            failed(format("invalid character: U+%04X",c));
        }
    }
    void checkCharData(ref string s) // rule 14
    {
		auto level = pushContext("CharData",s);
		scope(exit)
			popContext();

        while (true)
        {
			spaceCount(s);
			if (s.length == 0)
				break;
            if (s.startsWith("&")) 
				break;
            if (s.startsWith("<")) 
				break;
            if (s.startsWith("]]>")) 
				failed("]]> found within char data");
            s = s[1..$];
        }
    }

    void checkDocTypeDecl(ref string s) // rule 28
    {
        auto level = pushContext("DocTypeDecl",s);
		scope(exit)
			popContext();
        checkLiteral("<!DOCTYPE",s);
        //
        // TO DO -- ensure DOCTYPE is well formed
        // (But not yet. That's one of our "future directions")
        //
        checkEnd(">",s); // this is really not going to work for most DOCTYPE
    }

	void fullCheck(ref string s)
	{
        checkChars(s);
        checkDocument(s);
	}
}