module texi.read;

import texi.buffer;

import std.stdint;
import std.utf;
import std.stdio;
import std.range.interfaces;
//import std.range;
import core.exception;

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


class  InputArray(T) : InputRange!dchar
{
protected:
    const(T)[]  data_;
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
            // TODO: throw Exception
            front_ = 0x00;
            data_ = [];
        }

    }
    dchar moveFront()
    {
        dchar result = front;
        popFront();
        return result;
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

    int opApply(scope int delegate(dchar) dg)
    {
        int result = 0;
        while (!empty)
        {
            result = dg(front);
            popFront(); // 1 pop per call
            if (result != 0)
                return result;
        }
        return result;
    }
    int opApply(scope int delegate(uintptr_t, dchar) dg)
    {
        int result = 0;
        uintptr_t ct = 0;
        while (!empty)
        {
            result = dg(ct,front);
            popFront(); // one pop per call
            if (result != 0)
                return result;
            ct++;
        }
        return result;
    }
}

/**
ParseInputRange
    Wrap interface InputRange!dchar
    Has a pushFront stack.
    front, empty are direct properties.
    popFront checks pushFront stack
*/
/// number class returned by parseNumber
enum NumberClass
{
    NUM_ERROR = -1,
    NUM_EMPTY,
    NUM_INTEGER,
    NUM_REAL
};

/** ParseInputRange is not a strict input range, inherits no interface */
class ParseInputRange
{
public:
    dchar               front;
    bool                empty;
protected:
    Buffer!dchar	    stack_;
    InputRange!dchar    input_;
public:

    this(InputRange!dchar ir)
    {
        input_ = ir;
        popFront(); // get the status
    }


    void pushFront(dchar c)
    {
        if (!empty)
            stack_.put(front);
        else
            empty = false;
        front = c;

    }
    /// push a bunch of UTF32 characters in front of everything else, in reverse.
    void pushFront(const(dchar)[] s)
    {
        if (s.length == 0)
            return;
        if (!empty)
            stack_.put(front);
        else
            empty = false;
        auto slen = s.length;
        while (slen-- > 1)
            stack_.put(s[slen]);
        front = s[0];
    }

    void popFront()
    {
        if (stack_.length > 0)
        {
            front = stack_.back();
			stack_.popBack();
            return;
        }
        input_.popFront();
        empty = input_.empty;
        if (!empty)
            front = input_.front;

    }

    dchar moveFront()
    {
        dchar result = front;
        popFront();
        return result;
    }
// includes linefeed, tab, carriage return
    int getSpaceCt(dchar* lastSpace = null)
    {
        int   count = 0;
        dchar space = 0x00;
        while(!empty)
        {
            switch(front)
            {
                case 0x20:
                case 0x0A:
                case 0x09:
                case 0x0D:
                    space = front;
                    count++;
                    popFront();
                    break;
                default:
                    if (lastSpace)
                        *lastSpace = space;
                    return count;
            }
        }
        return 0;
    }

    bool stopAfterChar(dchar c)
    {
        while(!empty)
        {
            if (front == c)
            {
                popFront();
                return true;
            }
            popFront();
        }
        return false;
    }

    alias bool delegate(dchar c) CharTestDg;
    // return if f(dchar) returns true
    bool stopAfterTest(CharTestDg f)
    {
        while(!empty)
        {
            if (f(front))
            {
                popFront();
                return true;
            }
            popFront();
        }
        return false;
    }
    bool readToken(W) (dchar stopChar, auto ref W wr)
    {
        bool hit = false;
    SCAN_LOOP:
        for(;;)
        {
            if (empty)
                break;
            if (front == stopChar)
                break SCAN_LOOP;
            wr.put(front);
            popFront();
            hit = true;
        }
        return hit;
    }

    uintptr_t readLine(T)(ref Buffer!T w, dchar eolChar = '\n')
    {
        w.reset();
        while(!empty)
        {
            auto test = front;
            if (test == eolChar)
                break;
            w ~= test;
            popFront();
        }
        return w.length;
    }
    bool readToken(W) (dstring sepSet, auto ref W wr)
    {
        bool hit = false;
    SCAN_LOOP:
        for(;;)
        {
            if (empty)
                break;
            auto test = this.front;
            foreach(dchar sep ; sepSet)
                if (front == sep)
                    break SCAN_LOOP;
                wr.put(test);
                popFront();
                hit = true;
        }
        return hit;
    }
    NumberClass
    parseNumber(W)(auto ref W wr,  int recurse = 0 )
    {
        int   digitct = 0;
        bool  done =  empty;
        bool  decPoint = false;
        for(;;)
        {
            if (done)
                break;
            auto test = front;
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
                                popFront(); // pop the test character
                                Buffer!dchar tempWr;

                                if (parseNumber(tempWr, recurse+1)==NumberClass.NUM_INTEGER)
                                {
                                    wr.put(test);
                                    wr ~= tempWr.data;
                                    return NumberClass.NUM_REAL; // TODO: if no decimal point, and exponent is +ve, then could also be integer
                                }
                                else {
                                    // TODO: unit is this really OK? Might be a good place for exception
                                    // Got stuff we shouldn't have
                                    pushFront(tempWr.data);
                                    pushFront(test);
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
            wr ~= test;
            popFront();
            done = this.empty;
        }
        if (decPoint)
            return NumberClass.NUM_REAL;
        if (digitct == 0)
            return NumberClass.NUM_EMPTY;
        return NumberClass.NUM_INTEGER;
    }
    bool unquote(W)(ref W w)
    {
        if (empty)
            return false;
        if ((front=='\"')||(front=='\''))
        {
            dchar endQuote = front;
            popFront();
            while(!empty)
            {
                if (front==endQuote)
                {
                    popFront();
                    return true;
                }
                else {
                    w ~= front;
                    popFront();
                }
            }
        }
        return false;
    }

    bool match(T)(const(T)[] s)
    {
        if(s.length == 0 || empty)
            return false;

        auto ir = ReadRange!T(s);
        Buffer!dchar tempStack_;

        while(!empty && !ir.empty)
        {
            if (ir.front() != front)
            {
                // not goint to match, push stuff back
                if (tempStack_.length > 0)
                {
                    pushFront(tempStack_.data);
                }
                return false;
            }
            else {
                tempStack_ ~= front;
            }
            ir.popFront();
            popFront();
        }
        return ir.empty;
    }

    bool match(dchar c)
    {
        if (front != c)
            return false;

        popFront();
        return true;
    }
}



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




