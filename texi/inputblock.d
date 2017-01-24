module texi.inputblock;

import std.stdint;
import std.stdio;
import std.range.interfaces;
import std.traits;
import std.path;
import std.conv;
import texi.bomstring;
import texi.gcstats;
import texi.inputEncode;
import texi.buffer;
import std.utf;
import std.uni;

/**
    FileInputBlock(T) : read  next block of T from a file, or fixed buffer
*/
   enum IBLevel {
        ERROR = 2,
        FATAL = 3
    };


class InputBlockError : Exception {
public:
    IBLevel  level_;
    this(string msg, IBLevel level = IBLevel.ERROR,
        string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
        level_ = level;
    }
    IBLevel level() @property const
    {
        return level_;
    }
};

interface DCharProvider  {
    dchar[] transfer(dchar[] fillMe);
    bool    setEncoding(string encoding);
    bool    setBom(ByteOrderMark bom);
    bool    setFile(File s);
}

class InputBlock(T) : DCharProvider
{
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

    static if (is(T==char))
    {
        alias RecodeCharFn EncodeFn;
        alias getRecodeCharFn  getEncodeFn;
        const auto defaultEncode = &recode_utf8;
    }
    else static if (is(T==wchar))
    {
        alias RecodeWCharFn EncodeFn;
        alias getRecodeWCharFn getEncodeFn;
        const auto defaultEncode = &recode_utf16;
    }
    else static if (is(T==dchar))
    {
        alias RecodeDCharFn EncodeFn;
        alias getRecodeDCharFn getEncodeFn;
        const auto defaultEncode = &recode_utf32;
    }

    bool getMoreSource(ProvideDgWant wants, ref T[] srcdata)
    {
        final switch(wants)
        {
        case ProvideDgWant.INIT_DATA:
            if ((actual_.length > 0) || fillData())
            {
                srcdata = actual_;
                return true;
            }
            srcdata = null;
            return false;
        case ProvideDgWant.MORE_DATA:
            actual_ = srcdata;
            if (fillData())
            {
                srcdata = actual_;
                return true;
            }
            srcdata = null;
            return false;
        case ProvideDgWant.DONE_DATA:
            actual_ = srcdata;
            return true;
        case ProvideDgWant.DATA_ERROR:
            return true; // cause throw exception
        }
    }

    private bool fillData()
    {
        if (actual_.length > 0)
            return true;
        if (eof_)
            return false;
        actual_ = s_.rawRead(data_);
        eof_ = s_.eof;
        if (eof_)
        {
            s_.close();
        }
        if (actual_.length > 0)
            return true;
        actual_ = null;
        return false;
    }

    override dchar[] transfer(dchar[] fillMe)
    {
        if (!eof_)
        {
            if (data_.length < fillMe.length)
            {
                data_ = new T[fillMe.length];
            }
        }
        if (!fillData())
        {
            return null;
        }
        fillMe.length = recode_(&getMoreSource, fillMe);
        return fillMe;
    }



    enum { INTERNAL_BUF = 4096 / T.sizeof }

    this()
    {
        recode_ = defaultEncode;
        version(GC_STATS)
			gcStatsSum.inc();

    }
    this(File ins)
    {
        setFile(ins);
 		version(GC_STATS)
			gcStatsSum.inc();
    }
	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
	}
    void setArray(T[] src)
    {
        data_ = src;
        actual_ = src;
        eof_ = true;
    }
    bool setFile(File s)
    {
        s_ = s;
        eof_ = false;
        return s_.isOpen();
    }


    bool setBom(ByteOrderMark bom)
    {
        // TODO: bom_ !is null, then already set up!
        bom_ = bom;
        encoding_ = bom_.key.toString();
        if ( bom_.charSize != T.sizeof)
        {
            return false; //TODO: throw something
        }
        recode_ = getEncodeFn(encoding_);
        return (recode_ != null);
    }

    override bool setEncoding(string encName)
    {
        recode_ = getEncodeFn(encName);
        return (recode_ !is null);
    }
    EncodeFn recode_;
    File  s_; //
    bool  eof_; // set before s_ eof?
    T[]  data_; // raw buffer
    T[]  actual_; // slice of raw buffer, actual length?
    string encoding_;
    ByteOrderMark bom_;
}

/**
Immutable inputs are hard to mix with non-immutable.
Assume recoding requirement is native UTF only,
and only dummy  file , bom, and setEncoding support.

*/

class InputNative(T) : DCharProvider {
public:
    this(const(T)[] data)
    {
        original_ = data;
        actual_ = data;
    }
    dchar[] transfer(dchar[] fillMe)
    {
        uintptr_t ix = 0;
        uintptr_t next = 0;
        while ( (next < actual_.length) && (ix < fillMe.length))
        {
            fillMe[ix++] = decode(actual_, next);
        }
        fillMe.length = ix;
        if (next < actual_.length)
            actual_ = actual_[next..$];
        else
            actual_ = null;
        return fillMe;
    }
    bool    setEncoding(string encoding)
    {
        return true;
    }
    bool    setBom(ByteOrderMark bom)
    {
        return true;
    }
    bool    setFile(File s)
    {
        return true;
    }

private:
    const(T)[]  original_;
    const(T)[]  actual_;

}

class RecodeInput : InputRange!dchar
{
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

    alias RecodeInput   SelfType;
    alias void delegate(bool) InputEmptyDg;

    /* InputEmptyDg notifyEmpty_;

    void notifyEmpty(InputEmptyDg ndg)
    {
        notifyEmpty_ = ndg;
    }
    **/
    void open(string f)
    {
        ubyte[] spill;
        bool  isEOF;

        fileName_ = buildNormalizedPath(absolutePath(f));

        auto finput = File(fileName_,"r");
        bom_ = readBOM(finput, spill, isEOF);
        if (isEOF)
        {
            empty_ = true;
            return;
        }
        if (bom_ !is null)
        {
            switch(bom_.charSize)
            {
            case 1:
                filler_ = new InputBlock!char;
                break;
            case 2:
                filler_ = new InputBlock!wchar;
                break;
            case 4:
                filler_ = new InputBlock!dchar;
                break;
            default:
                //TODO:crap out
                break;
            }
            if (filler_)
            {
                if (spill.length > 0)
                {
                    finput.seek(bom_.bom.length);
                }
                filler_.setBom(bom_);
                filler_.setFile(finput);
                popFront();
            }
        }
    }
    this()
    {
        newBufferSize_ = 4;
  		version(GC_STATS)
			gcStatsSum.inc();
    }
    ~this()
    {
 		version(GC_STATS)
			gcStatsSum.dec();

    }
    static SelfType fromNative(T)(const(T)[] src)
    {
       auto result = new RecodeInput();
       result.setNative(src);
       return result;

    }
    static SelfType fromArray(T)(T[] src)
    {
        auto result = new RecodeInput();
        result.setArray!T(src);
        return result;
    }

    static SelfType fromFile(string fileName)
    {
        auto result = new RecodeInput();
        result.open(fileName);
        return result;
    }

    void setNative(T)(const(T)[] src)
    {
        auto input = new InputNative!T(src);
        filler_ = input;
        popFront();
    }
    void setArray(T)(T[] src)
    {
        auto input = new InputBlock!T;
        input.setArray(src);
        filler_ = input;
        popFront();
    }

    @property dchar front()
    {
        return front_;
    }
    dchar moveFront()
    {
        return front_;
    }

    @property bool empty()
    {
        return empty_;
    }

    void popFront()
    {
        if (empty)
            return;
        frontPos_++;
        if (frontPos_ < src_.length)
        {
            front_ = src_[frontPos_];
        }
        else {
            // get some more!
            if (filler_ is null)
                empty_ = true;
            else
            {
                if (src_.length < newBufferSize_)
                {
                    src_ = new dchar[newBufferSize_];
                }
                src_ = filler_.transfer(src_);
                if (src_.length > 0)
                {
                    frontPos_ = 0;
                    front_ = src_[0];
                    if (src_.length < newBufferSize_)
                    {   // likely end of data
                        newBufferSize_ = src_.length;
                    }
                }
                else {
                    empty_ = true;
                    src_ = null;
                }
            }
        }
    }

    int opApply(scope int delegate(dchar d))
    {
        return 0;
    }
    int opApply(scope int delegate(size_t ct, dchar d))
    {
        return 0;
    }

    uintptr_t bufferSize() @property
    {
        return src_.length;
    }
    void bufferSize(uintptr_t chars) @property
    {
        newBufferSize_ = chars;
    }

    string shortContext()
    {
        auto ctx = src_[0..$];
        if (ctx.length > 40)
        {
            ctx.length = 40;
        }
        return text(ctx);
    }
    bool setEncoding(string encoding)
    {
        string bomKey = toUpper(encoding);
        if (bom_ !is null)
        {
            if( bom_.key.codeName == bomKey)
                return true;
            auto bother = ByteOrderRegistry.findBOM(bomKey);
            if (bother !is null)
            {
                if (bother.charSize != bom_.charSize)
                {
                    throw new InputBlockError(text("Incompatible encoding ", encoding),IBLevel.FATAL);
                }
            }
            else {
                if (bom_.bom.length > 0)
                    throw new InputBlockError(text("BOM Incompatible encoding ",bom_.key, " - ", encoding),IBLevel.FATAL);
            }
        }
        if (filler_.setEncoding(encoding))
        {
            newBufferSize_ = 1024;
            return true;
        }
        else {
            throw new InputBlockError(text("Encoding '", encoding, "' is not supported"));
        }
    }
    uintptr_t       frontPos_;
    uintptr_t       newBufferSize_;
    dchar[]         src_;
    dchar           front_;
    bool            empty_;
    DCharProvider   filler_;
    string          fileName_;
    ByteOrderMark   bom_;
    /* ensure buffer size increases after
       processing any declaration
    */

}


