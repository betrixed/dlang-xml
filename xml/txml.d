module xml.txml;

/*
 Various Xml parsing options have been templated for character type.
 to allow for interesting combinations of source documents.

 A critical choice for performance is the data structure used to implement XmlBuffer.
 XmlBuffer is used to accumulate segments of xml text.

 This module establishes some non-dependent enums, and those
 interfaces and classes which will change with the template character type argument.

 xmlt(T) and its code resources are used by nearly all of the other modules in this xml package.
 xml.txml establishes XmlEvent, IXmlErrorHandler, IXmlDocHandler  templated for a character type.

---------------
Copyright: Copyright Michael Rynn 2011 - 2016.
License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors:   Michael Rynn
 */

import std.typecons : tuple, Tuple;
import std.string, std.stdint, std.utf;
import std.algorithm;
import texi.buffer;
//import std.container.array;
import std.array;
import std.traits;
import std.conv;
import xml.xmlChar;
import xml.xmlError;
import xml.xmlAttribute;
import std.ascii;
import std.format;
version(GC_STATS)
	import texi.gcstats;

enum CharFilter
{
    filterOff, filterOn, filterAlwaysOff
}

/// Parameter names for parser.
enum string xmlAttributeNormalize = "attribute-normalize";
enum string xmlCharFilter = "char-filter";
enum string xmlNamespaces = "namespaces";
enum string xmlFragment = "fragment";

//alias void delegate() SourceEmptyDg;
//alias void delegate(Exception)	PreThrowDg;
/// Return a string for the error code


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
	XI_ENTITY_REF,
	XI_OTHER,		/// internal DOCTYPE declarations
	RET_NULL,  /// nothing returned
	ENUM_LENGTH, /// size of array to hold all the other values

}

enum NodeType
{
    None = 0,
	Element_node = 1,
	Attribute_node = 2,
	Text_node = 3,
	CDATA_Section_node = 4,
	Entity_Reference_node = 5,
	Entity_node = 6,
	Processing_Instruction_node = 7,
	Comment_node = 8,
	Document_node = 9,
	Document_type_node = 10,
	Document_fragment_node = 11,
	Notation_node = 12
};

enum EntityType { Parameter, General, Notation }

enum RefTagType { UNKNOWN_REF, ENTITY_REF, SYSTEM_REF, NOTATION_REF}

/// Kind of default value for attributes
enum AttributeDefault
{
    df_none,
    df_implied,
    df_required,
    df_fixed
}

/** Distinguish various kinds of attribute data.
The value att_enumeration means a choice of pre-defined values.
**/
enum AttributeType
{
    att_cdata,
    att_id,
    att_idref,
    att_idrefs,
    att_entity,
    att_entities,
    att_nmtoken,
    att_nmtokens,
    att_notation,
    att_enumeration
}

template xmlt(T) {
	alias immutable(T)[] XmlString;
    alias void delegate(in T[]) StringPutDg;

	static const XmlString xmlNamespaceURI = "http://www.w3.org/XML/1998/namespace";
	static const XmlString xmlnsURI = "http://www.w3.org/2000/xmlns/";
	// Handle painful differences in buffer implementations, to enable comparisons.
	// Maybe these get optimized away?
	version (BUF_NATIVE) {
		version (BUF_APPENDER) {
			import std.array;
			alias Appender!(T[]) XmlBuffer; // Faster than T[]
			T[] data(ref XmlBuffer xbuf)
			{
				return xbuf.data;
			}
			void reset(ref XmlBuffer xbuf)
			{
                xbuf.clear();
			}
			ulong length(ref XmlBuffer xbuf)
            {
                return xbuf.data.length;
            }
            void assign(ref XmlBuffer xbuf, const(T)[] val)
			{
                xbuf.clear();
                xbuf ~= val;
			}
			void append(ref XmlBuffer xbuf, const(char)[] val)
			{
				xbuf ~= val;
			}
			void assign(ref XmlBuffer xbuf, dchar val)
			{
                xbuf.clear();
                xbuf ~= val;
			}
	        void putCharRef(ref XmlBuffer xbuf, dchar cref, uint radix)
	        {
				//
				xbuf ~= '&';
				xbuf ~= '#';
	            if (radix==16)
	                xbuf ~= 'x';
				auto specstr = (radix==16) ? "%x" : "%d";
				auto spec = singleSpec(specstr);
				formatValue(xbuf, cast(uint)cref,spec);
				//formatValue(w,cast(uint)cref,spec);
	            xbuf ~= ';';
	        }
		}
		else
		{
			alias T[] XmlBuffer;

			T[] data(ref XmlBuffer xbuf)
			{
				return xbuf;
			}
			void reset(ref XmlBuffer xbuf)
			{
                xbuf.length = 0;
			}
			void assign(ref XmlBuffer xbuf, const(T)[] val)
			{
                xbuf = val.dup;
			}
			void append(ref XmlBuffer xbuf, const(char)[] val)
			{
				xbuf ~= to!(T[])(val);
			}
			void assign(ref XmlBuffer xbuf, dchar val)
			{
                xbuf.length = 0;
                xbuf ~= val;
			}
            ulong length(ref XmlBuffer xbuf)
            {
                return xbuf.length;
            }
            void putCharRef(ref XmlBuffer xbuf, dchar cref, uint radix)
	        {
				//
				xbuf ~= '&';
				xbuf ~= '#';
	            if (radix==16)
	                xbuf ~= 'x';
				auto specstr = (radix==16) ? "%x" : "%d";
				auto spec = singleSpec(specstr);
				auto w = appender!(T[])();
				formatValue(w, cast(uint)cref,spec);
				//formatValue(w,cast(uint)cref,spec);
				xbuf ~= w.data;
	            xbuf ~= ';';
	        }

		}
	}
	else {
		alias Buffer!T XmlBuffer; // Still faster than Appender. Does not scrub on shrink

		T[] data(ref XmlBuffer xbuf)
		{
			return xbuf.data;
		}
		void reset(ref XmlBuffer xbuf)
		{
            xbuf.shrinkTo(0);
		}
		void assign(ref XmlBuffer xbuf, const(T)[] val)
		{
            xbuf = val;
		}
		void append(ref XmlBuffer xbuf, const(char)[] val)
		{
			xbuf ~= val;
		}
		void assign(ref XmlBuffer xbuf, dchar val)
		{
            xbuf.length = 0;
            xbuf ~= val;
		}
        ulong length(ref XmlBuffer xbuf)
        {
            return xbuf.length;
        }
        void putCharRef(ref XmlBuffer xbuf, dchar cref, uint radix)
        {
			//
			xbuf ~= '&';
			xbuf ~= '#';
            if (radix==16)
                xbuf ~= 'x';
			auto specstr = (radix==16) ? "%x" : "%d";
			auto spec = singleSpec(specstr);
			formatValue(xbuf, cast(uint)cref,spec);
			//formatValue(w,cast(uint)cref,spec);
            xbuf ~= ';';
        }
	}

	alias XMLAttribute!T.XmlAttribute	XmlAttribute;
	alias XMLAttribute!T.AttributeMap   AttributeMap;

	void remove(ref AttributeMap attr, XmlString key)
	{
	}

    alias XmlString[dchar] CharEntityMap;
	// Its a class so can pass it around as pointer
	class XmlEvent {
		SAX			eventId;
		XmlString		data;
		AttributeMap	attributes;
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
			version(GC_STATS)
				gcStatsSum.inc();

		}
		~this()
		{
			version(GC_STATS)
				gcStatsSum.dec();

		}
	}

	interface IXmlErrorHandler
	{

		void checkErrorStatus();
		XmlError preThrow(XmlError ex);

		XmlErrorLevel pushError(string s, XmlErrorLevel level);


		Exception makeException(XmlErrorCode code);
		Exception makeException(string s, XmlErrorLevel level = XmlErrorLevel.FATAL);
		Exception caughtException(Exception x, XmlErrorLevel level = XmlErrorLevel.FATAL);
	}

	class XmlErrorImpl : IXmlErrorHandler
	{
		private {
			Buffer!string			errors_;
			XmlErrorLevel			maxError_;
		}
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
			version(GC_STATS)
				gcStatsSum.inc();

		}
		~this()
		{
			version(GC_STATS)
				gcStatsSum.dec();

		}
		XmlErrorLevel pushError(string s, XmlErrorLevel level)
		{
			errors_.put(s);
			if (maxError_ < level)
				maxError_ = level;
			return maxError_;
		}

		void checkErrorStatus(){}

		XmlError preThrow(XmlError e)
		{
			return e;
		}

		Exception makeException(XmlErrorCode code)
		{
			return new XmlError(getXmlErrorMsg(code));

		}
		Exception makeException(string s, XmlErrorLevel level = XmlErrorLevel.FATAL)
		{
			return new XmlError(s,level);
		}

		Exception caughtException(Exception x, XmlErrorLevel level = XmlErrorLevel.FATAL)
		{
			auto s = x.toString();
			pushError(s, XmlErrorLevel.FATAL);
			return preThrow(new XmlError(s, XmlErrorLevel.FATAL));
		}
	}
	interface IXmlDocHandler
	{
		void init(ref XmlEvent s); // Allows user to set own XmlEvent class derivative
		void startTag(const XmlEvent s); // tag, followed by attribute pairs
		void soloTag(const XmlEvent s);
		void endTag(const XmlEvent s); // tag
		void text(const XmlEvent s); // text
		void cdata(const XmlEvent s);
		void comment(const XmlEvent s);
		void instruction(const XmlEvent s); // Processing instruction name, content
		void declaration(const XmlEvent s); // declaration attribute name, value

		void startDoctype(Object parser);		// notify of Dtd processing start
		void endDoctype(Object parser);		// notify of Dtd completed
		void notation(Object n);				// Notation entity data reference
		/// currently up to StdEventSize , ie XmlDeclaration last eventId
		/// just return the entity name, not decoded

		void setErrorHandler(IXmlErrorHandler eh);

		// new Entity processing

		void entityRef(const XmlEvent s);
	}

	class NullDocHandler :  IXmlDocHandler {
		void init(ref XmlEvent s){} // Allows user to set own XmlEvent class derivative
		void startTag( const XmlEvent s){} // tag, followed by attribute pairs
		void soloTag(const XmlEvent s){}
		void endTag(const XmlEvent s){} // tag
		void text(const XmlEvent s){} // text
		void cdata(const XmlEvent s){}
		void comment(const XmlEvent s){}
		void instruction(const XmlEvent s){} // Processing instruction name, content
		void declaration(const XmlEvent s){} // declaration attribute name, value

		void startDoctype(Object parser){}		// notify of Dtd processing start
		void endDoctype(Object parser){}		// notify of Dtd completed

		void notation(Object n){}				// Notation entity data reference
		/// currently up to StdEventSize , ie XmlDeclaration last eventId
		/// just return the entity name, not decoded
		void entityName(const(T)[] s,bool inAttribute){}

		void setErrorHandler(IXmlErrorHandler eh){
			errorHandler_ = eh;
		}


		void entityRef(const XmlEvent s){}
		private:
			IXmlErrorHandler errorHandler_;
	}
}

static string badCharMsg(dchar c)
{
	auto val = cast(uint)c;
	if ( ((val >= 0xD800) && (val < 0xE000)) || ((val > 0xFFFD) && (val < 0x10000)) || (val > 0x110000))
		return format("Forbidden character range 0x%x\n", val);
	return format("bad character 0x%x [%s]\n", val, c);
}


/**
Read only character array range, output dchar.

struct  ReadRange(T)
{
private:
	const(T)[]	data_;
	uintptr_t   next_;
    dchar       front_;

    void readyFront()
	{
		if (data_.length > 0)
		{
			static if (is(T == dchar))
			{
				front_ = data_[0];
				next_ = 1;
			}
			else {
                next_ = 0;
                auto dataref = data_;
				front_ = decode(dataref, next_);
			}
		}
	}

public:
	this(const(T)[] s)
	{
		assign(s);
	}
	void assign(const(T)[] s)
	{
        data_ = s;
        readyFront();
	}


	void popFront()
	{
		if (data_.length > next_)
		{
            data_ = data[next_..$];
			readyFront();
		}
		else {
            front_ = 0x00;
            data_ = [];
		}

	}

	bool empty() @property
	{
        return (data_.length == 0);
	}

	dchar front() @property
	{
        return front_;
	}
    const(T)[] data() @property
    {
        return data_;
    }


}
*/


void putRadix(T,S)(ref T[] appd, S value,uint radix = 10)
if (isIntegral!S)
{
	static if (isSigned!S)
	{
		if (value < 0)
			put('-');
		value = -value;
	}
	char[value.sizeof * 8] buffer;
	uint i = buffer.length;

	if (value < radix && value < hexDigits.length)
	{
		appd ~= hexDigits[cast(size_t)value .. cast(size_t)value + 1];
		return;
	}
	do
	{
		ubyte c;
		c = cast(ubyte)(value % radix);
		value = value / radix;
		i--;
		buffer[i] = cast(char)((c < 10) ? c + '0' : c + 'A' - 10);
	}
	while (value);

	appd ~= buffer[i..$];
}
