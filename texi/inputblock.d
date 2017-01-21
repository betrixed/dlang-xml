module texi.inputblock;

import std.stdint;
import std.stdio;
import std.range.interfaces;
import texi.bomstring;
import texi.gcstats;
import texi.inputEncode;
import texi.buffer;


/**
    FileInputBlock(T) : read  next block of T from a file, or fixed buffer
*/

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

    bool getMoreSource(ProvideDgWant wants, ref T[] data)
    {
        final switch(wants)
        {
        case ProvideDgWant.INIT_DATA:
            if ((actual_.length > 0) || fillData())
            {
                data = actual_;
                return true;
            }
            data_ = null;
            return false;
        case ProvideDgWant.MORE_DATA:
            actual_ = data;
            if (fillData())
            {
                data_ = actual_;
                return true;
            }
            data_ = null;
            return false;
        case ProvideDgWant.UNUSED_DATA:
            actual_ = data;
            return true;
        case ProvideDgWant.DATA_ERROR:
            return true;
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

class RecodeInput : InputRange!dchar
{

    alias RecodeInput   SelfType;

    void open(string f)
    {
        ubyte[] spill;
        bool  isEOF;

        fileName_ = f;
        s_ = File(fileName_,"r");
        bom_ = readBOM(s_, spill, isEOF);
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
                    s_.seek(bom_.bom.length);
                }
                filler_.setBom(bom_);
                filler_.setFile(s_);
                popFront();
            }
        }
    }
    this()
    {
        newBufferSize_ = 4;
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
    bool setEncoding(string encoding)
    {
        if (filler_.setEncoding(encoding))
        {
            newBufferSize_ = 1024;
            return true;
        }
        return false;
    }
    uintptr_t       frontPos_;
    uintptr_t       newBufferSize_;
    dchar[]         src_;
    dchar           front_;
    bool            empty_;
    DCharProvider   filler_;
    File            s_;
    string          fileName_;
    ByteOrderMark   bom_;
    /* ensure buffer size increases after
       processing any declaration
    */

}


