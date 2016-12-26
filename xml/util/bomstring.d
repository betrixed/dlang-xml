module xml.util.bomstring;

import std.variant;
import std.file;
import std.bitmanip;
import std.conv;
import std.stdint;
import std.stdio;
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

alias Algebraic!(char[], wchar[], dchar[]) BomString;

enum BOM : int {
    NONE = -1,
    UTF8,
    UTF16LE,
    UTF16BE,
    UTF32LE,
    UTF32BE
};

alias immutable(ubyte)[]  BomArray;
/**
Hold useful information about each kind of File Byte Order Mark.
For use as a global registry.
Official name as string, the character storage type, number of bytes per character
*/

class FileBOM
{
    string		name;		// indexable name
    int	        bomEnum;			// associated phobos BOM enum, or -1
    int	        endianEnum;			// associated endian type, or -1
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
        FileBOM sb = cast(FileBOM) this;
        if (sb !is null)
            return cmp(this.name, sb.name);
        else
            return -1;
    }
}


__gshared FileBOM[intptr_t]	gFileBOM;

/// Used for no match found
__gshared FileBOM	gNoBOMMark;

__gshared static this()
{
    gNoBOMMark = new FileBOM("UTF-8", -1, -1, typeid(char));
    register(gNoBOMMark);

    register( new FileBOM("UTF-8", BOM.UTF8, -1, typeid(char), [0xEF, 0xBB, 0xBF]));

    register( new FileBOM("UTF-16LE", BOM.UTF16LE, Endian.littleEndian, typeid(wchar),[0xFF, 0xFE] ));
    register( new FileBOM("UTF-16BE", BOM.UTF16BE, Endian.bigEndian, typeid(wchar), [0xFE, 0xFF] ));

    register( new FileBOM("UTF-32LE", BOM.UTF32LE, Endian.littleEndian, typeid(dchar), [0xFF, 0xFE, 0, 0] ));
    register( new FileBOM("UTF-32BE", BOM.UTF32BE, Endian.bigEndian, typeid(dchar), [0, 0, 0xFF, 0xFE] ));
}

/// add  ByteOrderMark signatures
void register(FileBOM bome)
{
    gFileBOM[bome.bomEnum] = bome;
}

BomArray getBomBytes(intptr_t marktype)
{
    auto psb = marktype in gFileBOM;
    return (psb is null) ? null : (*psb).bomBytes;
}

/** Loop till all but one or zero BOM arrays are eliminated,
	and one BOM sequence is exactly matched.
    Assume nothing about data length or bom lengths.
*/

/**
 * Read beginning of a block stream, and return what appears to
 * be a valid ByteOrderMark class describing the characteristics of any
 * BOM found.   If there is no BOM, the instance ByteOrderRegistry.noMark will
 * be returned, describing a UTF8 stream, system endian, with empty BOM array,
 * and character size of 1.
 *
 * The buffer array will hold all values in stream sequence, that were read by the
 * function after reading the BOM. If no BOM was recognized the buffer array contains
 * all the values currently read from the stream. The number of bytes in buffer
 * will be a multiple of the number of bytes in the detected character size of the stream
 * (ByteOrderMark.charSize). If end of stream is encountered or an exception occurred
 * the eosFlag will be true.
 *
 */
ByteOrderMark readBOM(File s, ref ubyte[] result, out bool eosFlag)
{
    ubyte[1]		test;
	ubyte[]		bomchars;


    ByteOrderMark[] goodList = ByteOrderRegistry.list.dup;
    ByteOrderMark[] fullMatch;

    auto goodListCount = goodList.length;
    ByteOrderMark found = null;
    try
    {
        eosFlag = false;
        int  readct = 0;

        while (goodListCount > 0)
        {
            s.rawRead(test);
            readct++;
            bomchars ~= test;
            foreach(gx , bm ; goodList)
            {
                if (bm !is null)
                {
                    auto marklen = bm.bom.length;
                    if (readct <= marklen)
                    {
                        if (test[0] != bm.bom[readct-1])
                        {
                            // eliminate from array
                            goodList[gx] = null;
                            goodListCount--;
                        }
                        else if (readct == marklen)
                        {
                            fullMatch ~= bm;
                            goodList[gx] = null;
                            goodListCount--;
                        }
                    }
                }
            }
        }
        if (fullMatch.length > 0)
        {
            // any marks fully matched ?
            found = fullMatch[0];
            for(size_t fz = 1; fz < fullMatch.length; fz++)
            {
                if (found.bom.length < fullMatch[fz].bom.length)
                    found = fullMatch[fz];
            }
        }
        else
        {
            found = ByteOrderRegistry.noMark;
        }

        // need to read to next full charSize to have at least 1 valid character
        //bool validChar = true;
        while ((bomchars.length - found.bom.length) % found.charSize != 0)
        {
            s.rawRead(test);
            bomchars ~= test;
        }
        // return remaining valid characters read as ubyte array
        result = bomchars[found.bom.length .. $];
        return found;
    }
    catch(Exception re)
    {
        if (bomchars.length == 0)
        {
            result.length = 0;
            eosFlag = true;
            return ByteOrderRegistry.noMark;
        }
    }

    result = bomchars;
    return ByteOrderRegistry.noMark;
}
FileBOM stripBOM(ref ubyte[] data)
{
    auto boms = gFileBOM.values[];
    auto bmct = boms.length;
    auto bpos = 0;

    FileBOM vb;
	FileBOM lastMatch = gNoBOMMark;
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
immutable(T)[]
readFileBom(T)(string filename, ref int bomMark)
{
    bomMark = -1;
    std.stdio.File f = std.stdio.File();
	f.open(filename,"r");
	ubyte[] raw;

	if (f.isOpen)
	{
	    scope(exit)
            f.close();
        auto bufSize = f.size();
        if (bufSize ==  0)
           return null;
        raw = new ubyte[bufSize];
        f.rawRead(raw);
	}

    FileBOM bom = stripBOM(raw);
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
    auto fs = File(file,"w");
    ubyte[] raw;
    if (bomMark >= 0)
    {
        auto tattoo = getBomBytes(bomMark);
        final switch(cast(BOM)bomMark)
        {
        case BOM.NONE:
             assert(0);
        case BOM.UTF8:
            auto cstr = data.get!(char[]);
            raw = cast(ubyte[])cstr;
            break;
        case BOM.UTF16LE:
            auto wstr = data.get!(wchar[]);
            raw = toLittleEndian16(wstr);
            break;
        case BOM.UTF16BE:
            auto wstr = data.get!(wchar[]);
            raw = toBigEndian16(wstr);
            break;
        case BOM.UTF32LE:
            auto dstr = data.get!(dchar[]);
            raw = toLittleEndian32(dstr);
            break;
        case BOM.UTF32BE:
            auto dstr = data.get!(dchar[]);
            raw = toBigEndian32(dstr);
            break;
        }
        fs.rawWrite(tattoo);
        fs.rawWrite(raw);
    }
    else
    {
        auto cstr = data.get!strmc;
        raw = cast(ubyte[])cstr;
        fs.rawWrite(raw);
    }
    fs.close();
}
