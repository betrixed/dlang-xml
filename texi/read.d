module texi.read;

import std.stdint;
import std.utf;
static import std.ascii;
/**
Read only character array range, output dchar.
*/
struct  ReadRange(T)
{
protected:
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
parseNumber(R,W)(ref R rd, auto ref W wr,  int recurse = 0 )
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

							auto tempRd = rd;
							tempRd.popFront(); // pop the test character
							char[] tempWr;
							if (parseNumber(tempRd,tempWr, recurse+1)==NumberClass.NUM_INTEGER)
							{
                                rd = tempRd;
                                wr ~= (cast(char)test);
                                wr ~= tempWr;
								return NumberClass.NUM_REAL; // TODO: if no decimal point, and exponent is +ve, then could also be integer
                            }
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




// includes linefeed, tab, carriage return
int getSpaceCt(T)( ref ReadRange!T idata, ref dchar lastSpace)
{
	int   count = 0;
	dchar space = 0x00;
	while(!idata.empty)
	{
		dchar test = idata.front;
		switch(test)
		{
			case 0x20:
			case 0x0A:
			case 0x09:
			case 0x0D:
				space = test;
				count++;
				idata.popFront();
				break;
			default:
				lastSpace = space;
				return count;
		}
	}
	return 0;
}
// same as getSpaceCt, but stop after first new line character
int getLineSpaceCt(T)( ref ReadRange!T idata, ref dchar lastSpace)
{
	int   count = 0;
	dchar space = 0x00;
	while(!idata.empty)
	{
		dchar test = idata.front;
		switch(test)
		{
			case 0x20:
			case 0x09:
			case 0x0D:
				space = test;
				count++;
				idata.popFront();
				break;
            case 0x0A:
                lastSpace = 0x0A;
                count++;
                return count;
			default:
				lastSpace = space;
				return count;
		}
	}
	return 0;
}

int getCharCt(T,W)( ref ReadRange!T idata, ref W wdata)
{
	int count = 0;
	while(!idata.empty)
	{
		dchar test = idata.front;
		switch(test)
		{
			case 0x20:
			case 0x0A:
			case 0x09:
			case 0x0D:
				return count;
			default:
				wdata ~= test;
				count++;
				break;
		}
		idata.popFront;
	}
	return count;
}

/* Stops read just after character */
bool stopAfterChar(T)(ref ReadRange!T idata, dchar c)
{
	while(!idata.empty)
	{
		dchar test = idata.front;
		if (test == c)
		{
			idata.popFront();
			return true;
		}
		idata.popFront();
	}
	return false;
}

/* Stops read just after myWord , assumed to be space delimited*/
bool getWordInLine(T)(ref ReadRange!T rd, const(T)[] myWord)
{
    dchar lastSpace = 0x00;
    Buffer!char buf;
    while(!rd.empty)
    {
        int spaceCt = getSpaceCt(rd,lastSpace);
        if (lastSpace == 0x0A)
        {
            return false;
        }
        buf.reset();
        int charCt = getCharCt(rd,buf);
        if (buf.data == myWord)
        {
            return true;
        }
    }
    return false;
}

/** assumes only one buffer for whole read line */
bool getToNewLine(T,W)(ref ReadRange!T rd, ref W wbuf)
{
	if (rd.empty)
		return false;
	const(T)[] current = rd.data;
	if (stopAfterChar!T(rd,0x0A))
    {
    	const(T)[] nextLine = rd.data;
    	int diff = (cast(int)current.length - cast(int)nextLine.length)-1;
    	if (diff > 0)
    	{
    		const(T)[] lineData = current[0.. cast(uintptr_t)diff];
    		wbuf ~= lineData;
    		return true;
    	}
    }
    return false;
}

bool isNumber(NumberClass nc)
{
    return (nc == NumberClass.NUM_INTEGER) || (nc == NumberClass.NUM_REAL);
}

/**
    Abstract class template of ReadBuffer
*/
class ReadBuffer(T)
{
protected:
    bool eof_; // Just had LAST FILL!
public:

	this()
	{
		eof_ = true;
	}

    @property bool isEOF()
    {
        return eof_;
    }
    bool setEncoding(string encoding)
    {
        return false;
    }
    bool setBufferSize(uint bsize)
    {
        return false;
    }
    bool fillData(ref const(T)[] buffer, ref ulong sourceRef)
    {
        return false;
    }
}


class FileReadBuffer(T) :  ReadBuffer!(T)
{
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}


    File  s_; //
    ubyte[] data_; // raw buffer

    enum { INTERNAL_BUF = 4096 / T.sizeof }


    override bool fillData(ref const(T)[] fillme, ref ulong refPos)
    {
        if (data_ is null)
        {
            data_ = new ubyte[INTERNAL_BUF];
        }
        refPos = s_.tell() / T.sizeof; // reference in character units

        auto didRead = s_.rawRead(data_);
        if (didRead.length > 0)
        {
            fillme = (cast(T*) data_.ptr)[0..didRead.length / T.sizeof];
            return true;
        }
        return false;
    }

    this(string filename)
    {
        this(File(filename,"r"));
    }
    this(File ins)
    {
        super();
        s_ = ins;
        eof_ = false;
		version(GC_STATS)
			gcStatsSum.inc();
    }

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
	}
}

class InputCharRange(T)
{
    /// Delegate to refill the buffer with data,
    alias ReadBuffer!(T)	DataFiller;
    /// Delegate to notify when empty becomes true.
    alias void delegate() EmptyNotify;

	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

    protected
    {
		T[]					stack_; // push back
        //Buffer!(T[])		stack_; // push back
        bool				empty_;
        T					front_;

        const(T)[]			str_;  // alias of a buffer to be filled by a delegate
        size_t				nextpos_; // index into string

        DataFiller	        df_; // buffer filler
        EmptyNotify			onEmpty_;
        ulong				srcRef_;  // original source reference, if any

        /// push stack character without changing value of front_
        void pushInternalStack(T c)
        {
            stack_ ~= c;
        }
    }

    /// return empty property of InputRange
    @property
    public const final bool empty()
    {
        return empty_;
    }

    /// return front property of f
    @property
    public const final T front()
    {
        return front_;
    }
    protected
    {
        bool FetchMoreData(bool firstPop = false)
        in {
            assert(nextpos_ >= str_.length,"FetchMoreData buffer not empty");
        }
        body {
            if (df_ is null || df_.isEOF())
                return false;
            if (df_.fillData(str_, srcRef_) && str_.length > 0)
            {
                empty_ = false;
                // popFront call is bad, since this was likely called from a popFront.
                // however, if this is the very first character, called from pumpStart
                // then have to simulate popFront.
                if (firstPop)
                    popFront();
                else
                {
                    front_ = str_[0];
                    nextpos_ = 1;
                }
                return true;
            }
            return false;
        }
    }
public:
	this()
	{
		empty_ = true;
		version(GC_STATS)
			gcStatsSum.inc();
	}

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
	}

    /// notifyEmpty read property
    @property EmptyNotify notifyEmpty()
    {
        return onEmpty_;
    }
    /// notifyEmpty write property
    @property void notifyEmpty(EmptyNotify notify)
    {
        onEmpty_ = notify;
    }
    /// indicate position of datastream in original source
    @property final ulong sourceReference()
    {
        return srcRef_ + nextpos_;
    }

    /// Number of bytes per array item
    @property final uint sourceUnit()
    {
        return T.sizeof;
    }

    // subtract this from sourceReference to get the position of the buffer start
    @property final auto sourceOffset()
    {
        return nextpos_;
    }

	void entireText(const(T)[] data)
	{
		arraySource(data);
		pumpStart();
	}
    /// After setting this, require call to pumpStart
    void arraySource(const(T)[] data)
    {
        str_ = data;
        empty_ = true;
        srcRef_ = 0;
        nextpos_ = 0;
    }

    /// After setting this, require call to pumpStart
    @property void dataSource(DataFiller df)
    {
        df_ = df;
        empty_ = true;
        srcRef_ = 0;
        nextpos_ = 0;
    }

    /**
    	Only does anything if empty is already set to true, which
    	can be from setting the dataSource property. It will only then reset empty,
    	and try to prime the input with a popFront.
    	Returns !empty.
    */

    bool pumpStart()
    {
        if (!empty_)
            return true;

        if (df_ !is null)
        {
            empty_ = !FetchMoreData(true);
        }
        else
        {
            empty_ = (str_.length == 0);
            nextpos_ = 0;
            if (!empty)
                popFront();
        }
        return !empty_;
    }



    /// Push a single character in front of input stream
    final void pushFront(T c)
    {
        if (!empty_)
        {
            stack_ ~= front;
        }
        front_ = c;
        empty_ = false;
    }
    /// push a bunch of characters back in front of stream
    final void pushFront(const(T)[] s)
    {
        if (s.length == 0)
            return;

        if (!empty_)
        {
            // normal case
            stack_ ~= front_;
        }
        auto slen = s.length;
        while (slen-- > 1)
            stack_ ~= s[slen];
        front_ = s[0];
        empty_ = false;
    }

    /// push a bunch of characters back in front of stream
	final void convertPushFront(U : U[])(const(U)[] s)
    if (!is(typeof(U) == typeof(T)))
    {
        pushFront(to!(const(T)[])(s));
    }

    /** InputRange method to bring the next character to front.
    	Checks internal stack first, and if empty uses primary buffer.
    */
    void popFront()
    {
        if (empty_)
            throw new RangeError("popFront when empty",__LINE__);
		auto slen = stack_.length;
        if (slen > 0)
        {
			slen--;
            front_ = stack_[slen];
			stack_.length = slen;
            return;
        }
        if (nextpos_ < str_.length)
        {
            front_ = str_[nextpos_++];
        }
        else
        {
            empty_ = !FetchMoreData();
            if (empty_)
            {
                front_ = 0;
                if (onEmpty_)
                    onEmpty_();
            }
        }
    }
    /// Return the front character if not empty, no state change
    final const bool peek(ref T next)
    {
        if (!empty_)
        {
            next = front_;
            return true;
        }
        return false;
    }
    /// Return the front character if not empty, and call popFront
    final bool pull(ref T next)
    {
        if (!empty_)
        {
            next = front_;
            popFront();
            return true;
        }
        return false;
    }
    /** Change the number of characters returned at a time.
        It may or may not take effect only after refill.
    	For xml documents a small buffer size is used until the encoding
    	has been established.
    */
    final bool setBufferSize(uint bsize)
    {
        if (df_ !is null)
            return df_.setBufferSize(bsize);
        else
            return false;
    }
    /** Change the character encoding of the underlying datastream.
    	It may or may not take effect only after refill.
    */

    final bool setEncoding(string encoding)
    {
        if (df_ !is null)
            return df_.setEncoding(encoding);
        else
            return false;
    }

}