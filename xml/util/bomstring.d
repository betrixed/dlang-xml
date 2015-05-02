module xml.util.bomstring;

import std.variant;
import std.file;
import std.bitmanip;
import std.conv;
import std.stdint;
import std.stream;
import std.string;
import std.array;
import xml.util.buffer;
import xml.util.inputEncode;

/** BOM mark datatype detection, read and write files.
    Jesse Phillips idea.
    @author Michael Rynn
    @date Jan 2012

License: Free to use prior to human caused global species extinction.
*/

import std.system;
import std.path;

alias char[]  strmc;
alias wchar[] strmw;
alias dchar[] strmd;

alias Algebraic!(strmc,strmw,strmd) BomString;

alias immutable(ubyte)[]  BomArray;
/// A Byte Order Mark, or BOM, is more than just an enum. It stands for a number of associations,
/// such as official name, its endian arrangement, an associated character storage type, and consumes
/// either 0, 2,3,4 bytes at the beginning of a file.
class StreamBOM
{
    string		name;		// indexable name
    int	bomEnum;			// associated phobos BOM enum, or -1
    int	endianEnum;			// associated endian type, or -1
    TypeInfo	type;		// storage type ? or other type?, or unknown

    BomArray	bomBytes;		// bytes at start of file

    this(string encode, int mark = -1, int endian = -1, TypeInfo ti = null, BomArray tattoo = null )
    {
        this.name = encode;
        this.bomEnum = mark;
        this.endianEnum = endian;
        this.type = ti;
        this.bomBytes = tattoo;
    }
    /// key supports a hash
    override hash_t toHash()
    {
        hash_t result;
        foreach(c ; name)
        result = result * 11 + c;
        return result;
    }

    /// key as a string
    override  string toString()
    {
        return name;
    }

    /// key supports compare
    override int opCmp(Object s)
    {
        StreamBOM sb = cast(StreamBOM) this;
        if (sb !is null)
            return cmp(this.name, sb.name);
        else
            return -1;
    }
}


__gshared StreamBOM[intptr_t]	gStreamBOM;

/// Used for no match found
__gshared StreamBOM	gNoBOMMark;

__gshared static this()
{
    gNoBOMMark = new StreamBOM("UTF-8", -1, -1, typeid(char));
    register(gNoBOMMark);

    register( new StreamBOM("UTF-8", BOM.UTF8, -1, typeid(char), [0xEF, 0xBB, 0xBF]));

    register( new StreamBOM("UTF-16LE", BOM.UTF16LE, Endian.littleEndian, typeid(wchar),[0xFF, 0xFE] ));
    register( new StreamBOM("UTF-16BE", BOM.UTF16BE, Endian.bigEndian, typeid(wchar), [0xFE, 0xFF] ));

    register( new StreamBOM("UTF-32LE", BOM.UTF32LE, Endian.littleEndian, typeid(dchar), [0xFF, 0xFE, 0, 0] ));
    register( new StreamBOM("UTF-32BE", BOM.UTF32BE, Endian.bigEndian, typeid(dchar), [0, 0, 0xFF, 0xFE] ));
}

/// add  ByteOrderMark signatures
void register(StreamBOM bome)
{
    gStreamBOM[bome.bomEnum] = bome;
}

BomArray getBomBytes(intptr_t marktype)
{
    auto psb = marktype in gStreamBOM;
    return (psb is null) ? null : (*psb).bomBytes;
}

/** Loop till all but one or zero BOM arrays are eliminated,
	and one BOM sequence is exactly matched.
    Assume nothing about data length or bom lengths.
*/

StreamBOM stripBOM(ref ubyte[] data)
{
    auto boms = gStreamBOM.values[];
    auto bmct = boms.length;
    auto bpos = 0;

    StreamBOM vb;
	StreamBOM lastMatch = gNoBOMMark;
    while(true)
    {
        if (bpos < data.length)
        {
            ubyte test = data[bpos];
            // eliminate non matching boms.
			size_t maxbomb = 0;
            foreach(ref bm ; boms)
            {
				vb = bm;
                if (vb !is null)
                {
					auto blen = vb.bomBytes.length;
                    if (bpos < blen)
                    {
						if (data[bpos]==vb.bomBytes[bpos])
						{
							blen--;
							if (maxbomb < blen)
								maxbomb = blen;
							if (blen==bpos)
								lastMatch = vb;
							continue;
						}
						else {
							bm = null;
							bmct--;
						}
                    }
                }
            }
			if (bpos < maxbomb)
				bpos++;
			else
				break;
		}
    }
	if (bpos < data.length)
		data = data[bpos..$];
	else
		data = null;
	return lastMatch;
}

immutable(T)[] toArray(T)(wchar[] wc)
{

	static if (is(T==wchar))
	{
        immutable(T)[] result = (cast(immutable(T)*) wc.ptr)[0..wc.length];
		return result;
	}
	static if (is(T==dchar))
	{
		size_t dpos = 0;
		dchar[] dstr = new dchar[wc.length];
		decode_wchar(wc,dstr,dpos);
		dstr.length = dpos;
		return (cast(immutable(dchar)*) dstr.ptr)[0..dstr.length];
	}
	static if (is(T==char))
	{
		Buffer!char stuff = wc;
		return stuff.freeze();
	}
}
immutable(T)[] toArray(T)(dchar[] dc)
{
	static if (is(T==dchar))
	{
	    auto result =  (cast(immutable(dchar)*) dc.ptr)[0..dc.length];
		return result;
	}
	static if (is(T==wchar))
	{
		Buffer!wchar stuff = dc;
		return stuff.freeze();
	}
	static if (is(T==char))
	{
		Buffer!char stuff = dc;
		return stuff.freeze();
	}
}
immutable(T)[] toArray(T)(const(char)[] c)
{
	static if (is(T==char))
	{
	    auto result =  (cast(immutable(char)*) c.ptr)[0..c.length];
		return result;
	}
	static if (is(T==wchar))
	{
		Buffer!wchar stuff =  c;
		return stuff.freeze();
	}
	static if (is(T==dchar))
	{
		Buffer!dchar stuff =  c;
		return stuff.freeze();
	}
}
/// Using character type indicator, Read entire file as UTF string, wstring or dstring, return BOM enum or -1 if UTF8 default
immutable(T)[] readTextBom(T)(string filename, ref int bomMark)
{
    bomMark = -1;
    std.stream.File f = new std.stream.File();
	f.open(filename,FileMode.In);
	ubyte[] raw;

	if (f.isOpen)
	{
	    scope(exit)
            f.close();
        auto bufSize = f.available();
        if (bufSize ==  0)
           return null;
        raw = new ubyte[bufSize];
        f.readBlock(raw.ptr, bufSize);
	}

    StreamBOM bom = stripBOM(raw);
    bomMark = bom.bomEnum;

    switch(bomMark)
    {
    case BOM.UTF8:
		goto default;
    case BOM.UTF16LE:
		return toArray!T(cast(strmw) fromLittleEndian16(raw));
    case BOM.UTF16BE:
         return toArray!T(cast(strmw) fromBigEndian16(raw));
    case BOM.UTF32LE:
        return toArray!T(cast(strmd) fromLittleEndian32(raw));
    case BOM.UTF32BE:
		return toArray!T(cast(strmd) fromLittleEndian32(raw));
    default:
        return toArray!T(cast(strmc) raw);
    }
}

dchar[] fromBigEndian32(ubyte[] src)
{
    version(LittleEndian)
    {
        dchar[] mstrd = cast(dchar[]) src;
        auto dlen = src.length / dchar.sizeof;
        for (size_t ix = 0, rix = 0 ; ix < dlen; ix++, rix += 4)
        {
            ubyte[4] dummy = src[rix .. rix + 4];
            mstrd[ix] = bigEndianToNative!(dchar, 4)(dummy);
        }
        return mstrd;
    }
    else
    {
        return cast(dchar[]) src;
    }
}

dchar[] fromLittleEndian32(ubyte[] src)
{
    version(LittleEndian)
    {
        return cast(dchar[]) src;
    }
    else
    {
        dchar[] mstrd = cast(dchar[]) src;
        auto dlen = src.length / dchar.sizeof;
        for (size_t ix = 0, rix = 0 ; ix < dlen; ix++, rix += 4)
        {
            ubyte[4] dummy = src[rix .. rix + 4];
            mstrd[ix] = littleEndianToNative!(dchar, 4)(dummy);
        }
        return mstrd;
    }
}

wchar[] fromBigEndian16(ubyte[] src)
{
    auto wlen = src.length / wchar.sizeof;

    version (LittleEndian)
    {
        wchar[] mstrw = cast(wchar[])(src); // in place
        for (size_t ix = 0, rix = 0 ; ix < wlen; ix++, rix += 2)
        {
            ubyte[2] dummy = src[rix .. rix + 2];
			mstrw[ix] = bigEndianToNative!(wchar, 2)(dummy);
        }
        return mstrw;
    }
    else
    {
        return cast(wchar[]) src;
    }
}

wchar[] fromLittleEndian16(ubyte[] src)
{
    auto wlen = src.length / wchar.sizeof;
    version (LittleEndian)
    {
        return cast(wchar[]) src;
    }
    else
    {
        wchar[] mstrw = cast(wchar[]) src;
        for (size_t ix = 0, rix = 0 ; ix < wlen; ix++, rix += 2)
        {
            ubyte[2] dummy = src[rix .. rix + 2]; // dumb.
            mstrw[ix] = littleEndianToNative!(wchar, 2)(dummy);
        }
        return mstrw;
    }

}

ubyte[] toLittleEndian32(dchar[] src)
{
    version (LittleEndian)
    {
        return cast(ubyte[]) src;
    }
    else
    {

//TODO
    }
}

ubyte[] toBigEndian32(dchar[] src)
{
    version (BigEndian)
    {
        return cast(ubyte[]) src;
    }
    else
    {
        ubyte[] mstrd = cast(ubyte[])(src); // in place
        auto dlen = src.length;
        for (size_t ix = 0, rix = 0 ; ix < dlen; ix++, rix += 4)
        {
            mstrd[rix .. rix+4] = nativeToBigEndian(src[ix]);
        }
        return mstrd;
    }
}

ubyte[] toLittleEndian16(wchar[] src)
{
    version (LittleEndian)
    {
        return cast(ubyte[]) src;
    }
    else
    {
//TODO

    }
}

ubyte[] toBigEndian16(wchar[] src)
{
    version (BigEndian)
    {
        return cast(ubyte[]) src;
    }
    else
    {
        auto wlen = src.length;
        ubyte[] raw = cast(ubyte[])(src); // in place
        for (size_t ix = 0, rix = 0 ; ix < wlen; ix++, rix += 2)
        {
            //wchar dummy = src[ix];
            raw[rix..rix+2] = nativeToBigEndian(src[ix]);
        }
        return raw;
    }
}

/** Ready to create a new file, rename original as backup, erase old backup.
    Return name of backup if original existed else null.
*/
string backupOldFile(string file)
{

    if (exists(file))
    {
        string bak;
        string ext = extension(file);
        string base = (ext.length > 0) ? file[0..$-ext.length] : file;
        bak = text(base,".~bk");
        if (exists(bak))
            remove(bak);
        rename(file,bak);
        return bak;
    }
    return null;
}
/** Create file and prepend Bom bytes to file data  */
void writeFileWithBOM (string file, BomString data, intptr_t bomMark)
{
    File fs = new File(file,FileMode.Out);
    ubyte[] raw;
    if (bomMark >= 0)
    {
        auto tattoo = getBomBytes(bomMark);
        final switch(cast(BOM)bomMark)
        {
        case BOM.UTF8:
            auto cstr = data.get!strmc;
            raw = cast(ubyte[])cstr;
            break;
        case BOM.UTF16LE:
            auto wstr = data.get!strmw;
            raw = toLittleEndian16(wstr);
            break;
        case BOM.UTF16BE:
            auto wstr = data.get!strmw;
            raw = toBigEndian16(wstr);
            break;
        case BOM.UTF32LE:
            auto dstr = data.get!strmd;
            raw = toLittleEndian32(dstr);
            break;
        case BOM.UTF32BE:
            auto dstr = data.get!strmd;
            raw = toBigEndian32(dstr);
            break;
        }
        fs.writeBlock(tattoo.ptr, tattoo.length);
        fs.writeBlock(raw.ptr,raw.length);
    }
    else
    {
        auto cstr = data.get!strmc;
        raw = cast(ubyte[])cstr;
        fs.writeBlock(raw.ptr,raw.length);
    }
    fs.close();
}
