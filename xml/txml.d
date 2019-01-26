module xml.txml;

import std.typecons : tuple, Tuple;
import std.string, std.stdint, std.utf;
import std.algorithm;
import xml.util.buffer;
//import std.container.array;
import std.array;
import std.traits;
import std.conv;
import xml.isxml;
import xml.error;
import xml.attribute;
import std.ascii;
import std.format;
version(GC_STATS)
	import xml.util.gcstats;



/// Parameter names for parser.

//alias void delegate() SourceEmptyDg;
//alias void delegate(Exception)	PreThrowDg;
/// Return a string for the error code

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

template sxml(T) {
	alias immutable(T)[] XmlString;

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

	void remove(ref AttributeMap!T attr, XmlString key)
	{
	}

    alias XmlString[dchar] CharEntityMap;
	// Its a class so can pass it around as pointer
}

/**
Read only character array range, output dchar.
*/
struct  ReadRange(T)
{
	bool empty;
	dchar front;
	const(T)[]	data_;

	this(const(T)[] s)
	{
		data_ = s;
		empty = s.length == 0;
		popFront();
	}

	void popFront()
	{
		if (data_.length > 0)
		{
			static if (is(T == dchar))
			{
				front = data_[0];
				data_ = data_[1..$];
			}
			else {
				uintptr_t ix = 0;
				front = decode(data_, ix);
				data_ = data_[ix..$];
			}
		}
		else
			empty = true;
	}
}


/// number class returned by parseNumber
enum NumberClass
{
    NUM_ERROR = -1,
    NUM_EMPTY,
    NUM_INTEGER,
    NUM_REAL
};

/**
Parse regular decimal number strings.
Returns -1 if error, 0 if empty, 1 if integer, 2 if floating point.
and the collected string.
No NAN or INF, only error, empty, integer, or real.
process a string, likely to be an integer or a real, or error / empty.
*/

NumberClass
parseNumber(R,W)(R rd, auto ref W wr,  int recurse = 0 )
{
    int   digitct = 0;
    bool  done = rd.empty;
    bool  decPoint = false;
    for(;;)
    {
        if (done)
            break;
        auto test = rd.front;
        switch(test)
        {
			case '-':
			case '+':
				if (digitct > 0)
				{
					done = true;
				}
				break;
			case '.':
				if (!decPoint)
					decPoint = true;
				else
					done = true;
				break;
			default:
				if (!std.ascii.isDigit(test))
				{
					done = true;
					if (test == 'e' || test == 'E')
					{
						// Ambiguous end of number, or exponent?
						if (recurse == 0)
						{
							wr ~= (cast(char)test);
							rd.popFront();
							if (parseNumber(rd,wr, recurse+1)==NumberClass.NUM_INTEGER)
								return NumberClass.NUM_REAL;
							else
								return NumberClass.NUM_ERROR;
						}
						// assume end of number
					}
				}
				else
					digitct++;
				break;
        }
        if (done)
            break;
        wr ~= (cast(char)test);
        rd.popFront();
        done = rd.empty;
    }
    if (decPoint)
        return NumberClass.NUM_REAL;
    if (digitct == 0)
        return NumberClass.NUM_EMPTY;
    return NumberClass.NUM_INTEGER;
};



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
