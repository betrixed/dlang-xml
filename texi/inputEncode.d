
/**
Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.

Distributed under the Boost Software License, Version 1.0.
Part of std.xmlp package reimplementation of std.xml.

Provides character decoding support to module xml.charinputs

Templates RecodeChar(T), RecodeWChar(T) and RecodeDChar(T) take either a delegate, function
or an InputRange with a pull method,
which makes it not an InputRange, but earlier versions used InputRange.

----
//The functions return whether or not a request for character type succeeded.

	bool delegate(ref T inChar);
	bool function(ref T inChar);
	bool pull(ref T inChar);

//  Input Range implementation of pull.
bool pull(ref SourceCharType c)
{
	if (empty)
		return false;
	c = front
	popFront();
}

// these either return a character or tell the caller it cannot be done.
alias bool delegate(ref char c)  Char8pull;
alias bool delegate(ref wchar c) Char16pull;
alias bool delegate(ref dchar c) Char32pull;

// RecodeDgFn.  Each function type uses the corresponding delegate
alias bool function(Char8pull src, ref dchar c) Recode8Fn;
alias bool function(Char16pull src, ref dchar c) Recode16Fn;
alias bool function(Char32pull src, ref dchar c) Recode32Fn;

---
*/
module texi.inputEncode;

import core.exception;
import std.system, std.stdint, std.stdio;
import std.conv, std.string, std.traits, std.exception;
import texi.buffer;

/// The character sequence was broken unexpectedly, or had an illegal encoding character.
class CharSequenceError :  Exception
{
    this(string s)
    {
        super(s);
    }
};

/// Throw a CharSequenceError for invalid character.
Exception invalidCharacter(dchar c)
{
    string msg = format("Invalid character {%x}", c);

    return new CharSequenceError(msg);
}

/+void indexError()
{
    throw new CharSequenceError("index past array length");
}
+/

/// Throw a CharSequenceError for broken UTF sequence
void breakInSequence()
{
    throw new CharSequenceError("Broken character sequence");
}

/// home made method for byte swapping
align(1) struct cswap
{
    char c0;
    char c1;
}

/// Home made byte swapper for 16 bit byte order reversal
align(1) union wswapchar
{
    cswap c;
    wchar w0;
}

/// Home made 32 bit byte swapper
align(1) struct cswap4
{
    char c0;
    char c1;
    char c2;
    char c3;
}
/// Home made byte swapper for 32 bit byte order reversal
align(1) struct dswapchar
{
    cswap4  c;
    dchar   d0;
}


private static const wstring windows1252_map =
    "\u20AC\uFFFD\u201A\u0192\u201E\u2026\u2020\u2021" ~
    "\u02C6\u2030\u0160\u2039\u0152\uFFFD\u017D\uFFFD" ~
    "\uFFFD\u2018\u2019\u201C\u201D\u2022\u2103\u2014" ~
    "\u02DC\u2122\u0161\u203A\u0153\uFFFD\u017E\u0178";


/** Provide a way of getting more characters, eg from a file.
   Provide a way of returning the unused part of source, when destination full.
*/
enum ProvideDgWant {
    // setup array reference with more data, such that length > 0
    INIT_DATA = 0,
    // save array reference to unused data

    MORE_DATA = 1,
    DONE_DATA = 2,

    /* invalid character, and unused data.
       Return true to throw invalidChar exception, false to abort */
    DATA_ERROR = 3
    };

// delegates and function types
alias bool delegate(ProvideDgWant wants, ref char[] src) MoreCharDg;
alias uintptr_t function(MoreCharDg dg, dchar[] dest) RecodeCharFn;

alias bool delegate(ProvideDgWant wants, ref wchar[] src) MoreWCharDg;
alias uintptr_t function(MoreWCharDg dg, dchar[] dest) RecodeWCharFn;

alias bool delegate(ProvideDgWant wants, ref dchar[] src) MoreDCharDg;
alias uintptr_t function(MoreDCharDg dg, dchar[] dest) RecodeDCharFn;

uintptr_t
recode_utf8(MoreCharDg dg, dchar[] dest)
{
    uintptr_t ix = 0;
    char[]  src;

    void choke(dchar d)
    {
        if (dg(ProvideDgWant.DATA_ERROR, src))
        {
            throw invalidCharacter(d);
        }
    }

    bool refill()
    {
        if (src is null)
        {
            return dg(ProvideDgWant.INIT_DATA, src);
        }
        else {
             return dg(ProvideDgWant.MORE_DATA, src);
        }
    }
    while (ix < dest.length)
    {
        if (src.length == 0)
        {
            if (!refill())
                return ix;
        }
        dchar d32 = src[0];

        if (d32 < 0x80)
        {
            dest[ix++] = d32;
            src = src[1..$]; //! OK, so advance
            continue;
        }

        if (d32 < 0xC0)
        {
             choke(d32);
             return ix;
        }

        int tails = void;
        if (d32 < 0xE0)// to 07FF
		{
            tails = 1;
            d32 = d32 & 0x1F;
        }
        else if (d32 < 0xF0) // to FFFF
        {
            tails = 2;
            d32 = d32 & 0x0F;
        }
        else if (d32 < 0xF8) // to 1FFFFF
        {
            tails = 3;
            d32 = d32 & 0x07;
        }
        else if (d32< 0xFC) // to 3FFFFFF
        {
            tails = 4;
            d32 = d32  & 0x03;
        }
        else
        {
            choke(d32);
            return ix;
        }
        src = src[1..$]; //! OK, so advance
        while(tails--)
        {
            if (src.length == 0)
            {
                if (!refill())
                    return ix;
            }
            d32 = (d32 << 6) + (src[0] & 0x3F);
            src = src[1..$];
        }
        dest[ix++] = d32;
    }
    // allow save state
    dg(ProvideDgWant.DONE_DATA,src);
    return ix;
}


/// Windows 1252 8 bit recoding
uintptr_t
recode_windows1252(MoreCharDg dg, dchar[] dest)
{
    uintptr_t ix = 0;
    char[] source;
    void choke(dchar d)
    {
        if (dg(ProvideDgWant.DATA_ERROR, source))
        {
            throw invalidCharacter(d);
        }
    }
    bool refill()
    {
        if (source is null)
        {
            return dg(ProvideDgWant.INIT_DATA, source);
        }
        else {
            return dg(ProvideDgWant.MORE_DATA, source);
        }
    }
    while (ix < dest.length)
    {
        if (source.length == 0)
        {
            if (!refill())
                return ix;
        }
        dchar test = source[0];
        source = source[1..$];
        dchar result = (test >= 0x80 && test < 0xA0) ? windows1252_map[test-0x80] : test;
        if (result == 0xFFFD)
        {
            choke(test);
            return ix;
        }
        else
        {
            dest[ix++] = result;
        }
    }
    dg(ProvideDgWant.DONE_DATA,source);
    return ix;
}
/// For Latin 8 bit recoding
uintptr_t recode_latin1(MoreCharDg dg, dchar[] dest)
{
    uintptr_t ix = 0;
    char[] source;
    bool refill()
    {
        if (source is null)
        {
            return dg(ProvideDgWant.INIT_DATA, source);
        }
        else {
            return dg(ProvideDgWant.MORE_DATA, source);
        }
    }
    while (ix < dest.length)
    {
        if (source.length == 0)
        {
            if (!refill())
                return ix;
            assert(source.length > 0);
        }

        dest[ix++] = source[0];
        source = source[1..$];
     }
    dg(ProvideDgWant.DONE_DATA,source);
    return ix;
}

/// For plain ASCII 7-bit recoding
uintptr_t recode_ascii(MoreCharDg dg, dchar[] dest)
{
    uintptr_t ix = 0;
    char[] source;
    void choke(dchar d)
    {
        if (dg(ProvideDgWant.DATA_ERROR, source))
        {
            throw invalidCharacter(d);
        }
    }
    bool refill()
    {
        if (source is null)
        {
            return dg(ProvideDgWant.INIT_DATA, source);
        }
        else {
            return dg(ProvideDgWant.MORE_DATA, source);
        }
    }
    while (ix < dest.length)
    {
        if (source.length == 0)
        {
            if (!refill())
                return ix;
        }

        dchar test = source[0];
        source = source[1..$];
        if (test >= 0x80)
        {
            choke(test);
            return ix;
        }
        dest[ix++] = test;
     }
    dg(ProvideDgWant.DONE_DATA,source);
    return ix;
}

private {
    __gshared RecodeCharFn[string] g8Decoders;

    __gshared static this()
    {
        register_CharFn("ISO-8859-1",&recode_latin1);
        register_CharFn("UTF-8",&recode_utf8);
        register_CharFn("ASCII",&recode_ascii);
        register_CharFn("WINDOWS-1252",&recode_windows1252);
    }


}
/// simple switch lookup
RecodeCharFn getRecodeCharFn(string name)
{
    string ucase = name.toUpper();
    auto fn = ucase in g8Decoders;
    return (fn is null) ?  null : *fn;
}
    /// Add more if required
void register_CharFn(string name, RecodeCharFn fn)
{
    string ucase = name.toUpper();
    g8Decoders[ucase] = fn;
}
/** Conversion of native UTF16 character array source to dchar buffer.
     Driven by dchar[] size and MoreCharDg capacity
*/


uintptr_t
recode_utf16(MoreWCharDg dg, dchar[] dest)
{
    uintptr_t ix = 0;
    wchar[]  source;
    void choke(dchar d)
    {
        if (dg(ProvideDgWant.DATA_ERROR, source))
        {
            throw invalidCharacter(d);
        }
    }
    bool refill()
    {
        if (source is null)
        {
            return dg(ProvideDgWant.INIT_DATA, source);
        }
        else {
            return dg(ProvideDgWant.MORE_DATA, source);
        }
    }
    while (ix < dest.length)
    {
        if (source.length==0)
        {
            if (!refill())
                return ix;
            assert(source.length > 0);
        }

        dchar d32 = source[0];
        source = source[1..$];

        if (d32 < 0xD800 || d32 >= 0xE000)
        {
            dest[ix++] = d32;
            continue;
        }
        if (source.length==0)
        {
            if (!refill())
            {
                choke(d32);
                return ix;
            }
            assert(source.length > 0);
        }
        dest[ix++] = cast(dchar) 0x10000 + ((d32 & 0x3FF) << 10) + (source[0] & 0x3FF);
        source = source[1..$];
    }
    dg(ProvideDgWant.DONE_DATA,source);
    return ix;
}

/** 16 bit characters may need endian byte swap **/

/** UTF-16 wrong endian to UTF-32 ?**/
uintptr_t recode_swap_utf16(MoreWCharDg dg, dchar[] dest)
{
    uintptr_t ix = 0;
    wchar[]  source;
    wswapchar swp = void;
    wswapchar result = void;

    void choke(wchar d)
    {
        if (dg(ProvideDgWant.DATA_ERROR, source))
        {
            throw invalidCharacter(d);
        }
    }
    bool refill()
    {
        if (source is null)
        {
            return dg(ProvideDgWant.INIT_DATA, source);
        }
        else {
            return dg(ProvideDgWant.MORE_DATA, source);
        }
    }
    while (ix < dest.length)
    {
        if (source.length==0)
        {
            if (!refill())
            {
                return ix;
            }
            assert(source.length > 0);
        }
        swp.w0 = source[0];
        source = source[1..$];

        result.c.c0 = swp.c.c1;
        result.c.c1 = swp.c.c0;

        if (result.w0 < 0xD800 || result.w0 >= 0xE000)
        {
            dest[ix++] = result.w0;
            continue;
        }

        dchar d = result.w0 & 0x3FF;
        if (source.length==0)
        {
            if (!refill())
            {
                choke(result.w0);
                return ix;
            }
            assert(source.length > 0);
        }
        swp.w0 = source[0];
        source = source[1..$];

        result.c.c0 = swp.c.c1;
        result.c.c1 = swp.c.c0;

        dest[ix++] = 0x10000 + ((result.w0 & 0x3FF) << 10) + d;
    }
    dg(ProvideDgWant.DONE_DATA,source);
    return ix;
}

/// select recode function based on name.
RecodeWCharFn getRecodeWCharFn(string name)
{
    string upcase = name.toUpper();
    switch(name)
    {
    case "UTF-16LE":
        if (endian == Endian.bigEndian)
            return &recode_swap_utf16;
        else
            return &recode_utf16;

    case "UTF-16BE":
        if (endian == Endian.bigEndian)
            return &recode_utf16;
        else
            return &recode_swap_utf16;

    case "UTF-16":
        return &recode_utf16;

    default:
        return null;
    }
}

uintptr_t recode_utf32(MoreDCharDg dg, dchar[] dest)
{
    uintptr_t ix = 0;
    dchar[] source;
    bool refill()
    {
        if (source is null)
        {
            return dg(ProvideDgWant.INIT_DATA, source);
        }
        else {
            return dg(ProvideDgWant.MORE_DATA, source);
        }
    }

    while (ix < dest.length)
    {
        if (source.length == 0)
        {
            if (!dg(ProvideDgWant.MORE_DATA,source))
                return ix;
            assert(source.length > 0);
        }
        dest[ix++] = source[0];
        source = source[1..$];
     }
    dg(ProvideDgWant.DONE_DATA,source);
    return ix;

}

RecodeDCharFn getRecodeDCharFn(string name)
{
    string upcase = name.toUpper();
    switch(name)
    {
    case "UTF-32":
    case "UTF-32BE":
    case "UTF-32LE":
        return &recode_utf32; //TODO: this must be wrong for some inputs
    default:
        return null;
    }
}


/// append a dchar to UTF-8 string

void appendUTF8(ref char[] s, dchar d)
{
    if (d < 0x80)
    {
        // encode in 7 bits, 1 byte
        s ~= cast(char) d;
        return;
    }
    else
    {
        if (d < 0x800)
        {
            // encode in 11 bits, 2 bytes
            char c2 = d & 0xBF;
            d >>= 6;
            s ~= cast(char) (d | 0xC0);
            s ~= c2;
            return;
        }
        else if (d < 0x10000)
        {
            // encode in 16 bits, 3 bytes
            char c3 = cast(char) (d & 0xBF);
            d >>= 6;
            char c2 = cast(char) (d & 0xBF);
            d >>= 6;
            s ~= cast(char) (d | 0xE0);
            s ~= c2;
            s ~= c3;
            return;
        }
        else if (d > 0x10FFFF)
        {
            // not in current unicode range?
            throw new RangeError("Unicode character greater than x10FFFF",__LINE__);
        }
        else
        {
            // encode in 21 bits, 4 bytes
            char c4 = cast(char) (d & 0xBF);
            d >>= 6;
            char c3 = cast(char) (d & 0xBF);
            d >>= 6;
            char c2 = cast(char) (d & 0xBF);
            d >>= 6;
            s ~= cast(char) (d | 0xF0);
            s ~= c2;
            s ~= c3;
            s ~= c4;
            return;
        }
    }
}

/// DecoderKey is a UTF code name, and BOM name pairing.

struct DecoderKey
{
    string codeName;
    string bomName;

    this(string encode,string bom = null)
{
    codeName = encode;
    bomName = bom;
}
/// key supports a hash
const hash_t toHash() nothrow @safe
{
    hash_t result;
    foreach(c ; codeName)
    result = result * 11 + c;

    if (bomName !is null)
        foreach(c ; bomName)
        result = result * 11 + c;
    return result;
}

/// key as a string
const  string toString()
{
    return text(codeName,bomName);
}

/// key supports compare
const int opCmp(ref const DecoderKey s)
{
    int result = cmp(this.codeName, s.codeName);
    if (!result)
    {
        if (this.bomName is null)
        {
            result = (s.bomName is null) ? 0 : -1;
        }
        else
        {
            result =  (s.bomName !is null) ? cmp(this.bomName, s.bomName) : 1;
        }
    }
    return result;
}
}


/** Associate the DecoderKey with its bom byte sequence,
 *  an endian value, and bits per character
 **/

class ByteOrderMark
{
    DecoderKey	key;
    ubyte[]		bom;
    Endian		endOrder;
    uint		charSize;

    this(DecoderKey k, ubyte[] marks, Endian ed, uint bsize)
{
    key = k;
    bom = marks;
    endOrder = ed;
    charSize = bsize;

}
};

/**
 * BOM and encoding registry initialisation
 **/

struct ByteOrderRegistry
{
    __gshared ByteOrderMark[]	list;

    /// Used for no match found
    __gshared ByteOrderMark	noMark;

    __gshared static this()
    {

        noMark = new ByteOrderMark(DecoderKey("UTF-8",null), [], endian, 1);
        registerBOM(new ByteOrderMark(DecoderKey("UTF-8",null), [0xEF, 0xBB, 0xBF], endian, 1));
        registerBOM(new ByteOrderMark(DecoderKey("UTF-16","LE"), [0xFF, 0xFE], Endian.littleEndian, 2));
        registerBOM(new ByteOrderMark(DecoderKey("UTF-16","BE"), [0xFE, 0xFF], Endian.bigEndian, 2));
        registerBOM(new ByteOrderMark(DecoderKey("UTF-32","LE"), [0xFF, 0xFE, 0x00, 0x00], Endian.littleEndian, 4));
        registerBOM(new ByteOrderMark(DecoderKey("UTF-32","BE"), [0x00, 0x00, 0xFE, 0xFF], Endian.bigEndian,4));
    }


    /// add  ByteOrderMark signatures
    static void registerBOM(ByteOrderMark bome)
    {
        list ~= bome;
    }
    /** Argument k must be upper case */
    static const(ByteOrderMark) findBOM(string k)
    {
        foreach(ByteOrderMark b ; list)
        {
            auto kname = b.key.codeName;
            if (indexOf(k, kname) == 0)
            {
                if (kname.length == k.length)
                    return b;
                auto kend = k[kname.length..$];
                if (kend == b.key.bomName)
                    return b;
            }
        }
        return null;
    }

}




