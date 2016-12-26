
/**
	Buffer(T) - Versatile appendable D array for buffer reuse, append, reset with preserved capacity.
	Has additional template specializations for char, wchar, dchar, which always has an extra space for appending a terminating null character.
	Magic property is no memory reallocation or capacity loss if length set to zero.
	Resulting speed ups from reduced memory manager work. Perhaps reduction in hardware cache misses.
	Almost a drop in replacement for T[]. Some features adopted from std.array and std.range
*/

/**
Authors: Michael Rynn

*/

module xml.util.buffer;

import std.utf;
import std.string;
import std.stdio;

import std.stdint;
import std.traits;
import core.stdc.string;
import std.conv;
import std.variant;
import std.exception;
import std.algorithm;
import std.ascii;
private import core.stdc.stdlib;
private import core.memory;

/// May be thrown by some index checks inside Buffer(T)
class BufferError : Exception
{
    this(string s)
    {
        super(s);
    }

	static BufferError makeIndexError(intptr_t ix)
	{
		return new BufferError(format("Out of bounds index %s", ix));
	}

    static void makeSliceError(uintptr_t p1, uintptr_t p2)
    {
        throw new BufferError(format("Slice error: %s to %s", p1, p2));
    }
}


import core.memory;

private {
enum alignBits = uintptr_t.sizeof;
enum alignMask = alignBits - 1;
enum alignData = ~alignMask;
}

/// Return next integer power of 2
T getNextPower2(T)(T k)
if (isIntegral!T) {
	if (k == 0)
		return 1;
	k--;
	for (int i=1; i < (T.sizeof * 8); i<<=1)
		k = k | (k >> i);
	return k+1;
}

/// starting from index pos, move up items which are T.init
/// return count of T.init found
uintptr_t removeInit(T)(T[] items, uintptr_t pos = 0)
{
	auto dp = items.ptr;

	if (dp is null || items.length == 0)
		return 0;

	auto ok = dp + pos;
	auto end = dp + items.length;
	while ( (ok < end) && (*ok !is T.init) )
		ok++;
	auto adv = ok + 1;
	while (adv < end)
	{
		if (*adv !is T.init)
		{
			*ok++ = *adv;
			*adv = T.init;
			adv++;
		}
		else
			adv++;
	}
	return items.length - (ok - dp);
}

/// The speed up for using the Buffer class over plain T[] is something like 8/3 or 2.6 times
/// At least this the ratio noted in the XmlParser for a short XML document.
/// Using T[] always triggers a reallocation every time length is set to zero.
/// A T[] cannot be reset and reused as is, which defeats the purpose of having a capacity.
/// Such reallocations also increase possibility of hardware cache misses.
/// std.array Appender is another possibility, but it is not a drop in replacement for T[]
/// Using Buffer can save a lot of memory reallocation, as maximum used capacity is preserved
/// For T = character type, the custom allocation includes 1 extra allocation unit beyond requested capacity for adding a terminating null without reallocation).
/// Null termination (calling nullTerminate()) will therefore never cause a re-allocation.

struct Buffer(T)
{
	/// Adapted from std.algorithm, with some assert conditions removed
    struct Range
    {
		// Writeable, and ignores reference count. Writes change without copyOnWrite
        private Buffer*			 _outer;
        private uintptr_t	 _a, _b;

		// Does not increment reference count
        this(Buffer* data, size_t a, size_t b)
        {
			assert((data != null) && (a <= b) && (b <= data.length_));
            _outer = data;
            _a = a;
            _b = b;
        }

		@property Range save()
        {
            return this;
        }
        @property bool empty() const
        {
            return _a >= _b;
        }
		@property size_t length() const
        {
            return _b - _a;
        }
		//??? outer_.length ??
        size_t opDollar() const
        {
            return _b - _a;
        }
        @property T front()
        {
            enforce(!empty);
            return _outer.ptr_[_a];
        }
		@property T back()
        {
            enforce(!empty);
            return _outer.ptr_[_b - 1];
        }
        void popFront()
        {
            enforce(!empty);
            ++_a;
        }

        void popBack()
        {
            enforce(!empty);
            --_b;
        }
        T moveFront()
        {
            enforce(!empty);
            return move( _outer.ptr_[_a] );
        }
        T moveBack()
        {
            enforce(!empty);
            return move(_outer.ptr_[_b - 1]);
        }

        T moveAt(size_t i)
        {
            i += _a;
            enforce(i < _b && !empty);
            return move(_outer.ptr_[i]);
        }

        T opIndex(size_t i)
        {
            i += _a;
            enforce(i < _b);
            return _outer.ptr_[i];
        }
        void opIndexAssign(T value, size_t i)
        {
            i += _a;
            enforce(i < _b);
            _outer.ptr_[i] = value;
        }

        void opIndexOpAssign(string op)(T value, size_t i)
        {
            i += _a;
            enforce(i < _b);
            mixin("_outer[i] "~op~"= value;");
        }
        typeof(this) opSlice()
        {
            return this;
        }

        typeof(this) opSlice(size_t a, size_t b)
        {
            a += _a;
            b += _a;
            enforce(a <= b && b <= _b);
            return typeof(this)(_outer, a, b);
        }
        void opSliceAssign(T value)
        {
            _outer.ptr_[_a .. _b] = value;
        }
	}

	alias Buffer!T			ThisType;

	/** ensure that data is copied */
	void copy(ref ThisType po)
	{
		if (&this == &po)
			return;
		assign(po.ptr_, po.length);
	}
    /** Set pointer to null, length and capacity to 0 */
	final void forget()
	{
		ptr_ = null;
		length_ = 0;
		capacity_ = 0;
	}

	/** Take ownership of data from argument */
	void takeOver(ref ThisType po)
	{
		if (&this == &po)
			return;
		if (ptr_ != null)
		{
			assert(ptr_ != po.ptr_);
			forget();
		}
		ptr_ = po.ptr_;
		length_ = po.length_;
		capacity_ = po.capacity_;
		po.forget();
	}
/// Read capacity property
    uintptr_t capacity() const @property
    {
        return (ptr_ is null) ? 0 : capacity_;
    }
/// Read pointer property
    T* ptr()
    {
        if (!ptr_)
            return null;
        return ptr_;
    }
/// Read length property
    uintptr_t length() const @property
    {
        return (ptr_ is null) ? 0 : length_;
    }
	/// mimic of Appender interface, only allow shrink
	void shrinkTo(uintptr_t x)
	{
		if (ptr_ && (x < length_))
		{
			static if (!isScalarType!(T))// else already marked as having no pointers
			{
				destroy_data(ptr_+x, length_ - x);
			}
			length_ = x;
		}
	}
/// Change length. May call constructor or destructor for non-simple T
	void length(uintptr_t x) @property
	{
		if (ptr_)
		{
			size_t oldlen = length_;
			if (oldlen == x)
				return;

			if (oldlen > x)
			{
				static if (!isScalarType!(T))
				{
					destroy_data(ptr_+x, oldlen - x);
				}
				length_ = x;
			}
			else {
				auto scap = capacity_;
				if (x > scap)
				{
					reserve(x); // ptr_ expected to change
				}
				length_ = x;
				static if (!isScalarType!(T))
				{
					init_create(ptr_ + oldlen, x - oldlen);
				}
			}
			return;
		}
		reserve(x);
		length_ = x;
		static if (!isScalarType!(T))
		{
			init_create(ptr_,x);
		}
	}
    /// Const pointer to internal buffer
    const(T)* constPtr() const @property
    {
		return ptr_;
    }

	private {
        /// ensure capacity for an additional number of items.
        void roomForExtra(uintptr_t extra)
        {
            immutable newCap = length_ + extra;
            if (newCap > capacity_)
                reserve(newCap);
        }
        static void init_create(T)(T* dest, size_t nlen)
        {
            T* end = dest + nlen;
            while(dest < end)
            {
                *dest = T.init;
                dest++;
            }
        }

        static
        void copy_create(T* dest, const(T)* src, size_t nlen)
        {
            T* end = dest + nlen;
            while(dest < end)
            {
                *dest = * cast(T*) (cast(void*) src);
                dest++;
                src++;
            }
            //new (dest) T(*src);
        }

        static
        void destroy_data(T* dest, size_t nlen)
        {
            T* end = dest + nlen;
            while(dest < end)
            {
                static if (hasElaborateDestructor!(T))
                    typeid(T).destroy(dest);
                else
                    *dest = T.init;
                dest++;
            }
        }
        static
        void freeCapacity(T* data,bool doFree = false)
        {
            if (data is null)
                return;
            if (doFree)
                GC.free(data);
        }

        static
        T* createCapacity(ref uintptr_t kap, bool exactLen = false)
        {
            // No point in being APPENDABLE if always making a new block.
            auto doScan = typeid(T[]).next.flags & 1;  // some indication that T contains pointers?

            static if (isSomeChar!T)
            {
                uintptr_t nullSpace =  T.sizeof; // zero termination always possible.
            }
            else {
                uintptr_t nullSpace =  0;
            }

            uintptr_t allocSize = kap * T.sizeof + nullSpace;
            /// round it up, maybe fit memory manager better
            if (!exactLen)
                allocSize = getNextPower2!uintptr_t(allocSize);

            auto info = GC.qalloc(allocSize, (doScan) ? 0 : GC.BlkAttr.NO_SCAN);
            auto data = cast(T*) info.base;
            memset(data, 0, allocSize);
            auto newcap = (info.size - nullSpace) / T.sizeof;


            assert(newcap >= kap);
            kap = newcap;
            return data;
        }
	}
	/// Get a writeable range.
    Range opSlice()
    {
        return Range(&this, 0, length);
    }
	/// Get a writeable range.
    Range opSlice(size_t a, size_t b)
    {
        enforce(a <= b && b <= length_);
        return Range(&this, a, b);
    }

    /// Ensure at least a minimum capacity, greater or equal to current length.
    /// Rounds up to a next power of 2, unless exactLen is true.
	void reserve (uintptr_t len, bool exactLen = false)
	{
		if (ptr_ is null)
		{
			ptr_ =  createCapacity(len,exactLen);
			if (ptr_ !is null)
				capacity_ = len;
			debug(TrackCount)
			{
				ptr_.codeline_ = id_;
				addTrack(ptr_);
			}
			return;
		}

		auto oldcap =  capacity_;

		if (len > oldcap)
		{
			// more than current capacity, current length_ <= oldcap
			auto newdata = createCapacity(len);
			capacity_ = len;

			if (length_ > 0) //must have set length to 0 if doing assign
			{
				auto len_copy = length_;
				memcpy(newdata, ptr_, len_copy*T.sizeof);
				length_ = len_copy;
			}
			freeCapacity(ptr_);

			ptr_ = newdata;
		}
		else {
			// can only shrink down to current length, or do nothing

		}
	}
	/// Replace
	void assign(const(T)* buf, size_t slen)
	{
		if (slen == 0)
		{
			length(0);
			return;
		}
		reserve(slen, true);
		copy_create(ptr_, buf, slen);
		length_ = slen;
	}
	void opAssign(immutable(T)[] s)
	{
		if (s !is null)
			assign(s.ptr, s.length);
		else
			length = 0;
	}
	void opAssign(const(T)[] s)
	{
		if (s !is null)
			assign(s.ptr, s.length);
		else
			length = 0;
	}



    void put(T c)
    {
		roomForExtra(1);
        (ptr_)[length_++] = c;
    }


    static if (isSomeChar!(T))
    {
        void putInteger(S)(S value,uint radix = 10)
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
                opCatAssign(hexDigits[cast(size_t)value .. cast(size_t)value + 1]);
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
            opCatAssign(buffer[i..$]);
        }

        @property immutable(T)[]  freeze()
        {
            if (ptr_ is null)
                return null;
            auto result = (cast(immutable(T)*)ptr_)[0..length_];
            ptr_ = null;
            length_ = 0;
            return result;
        }
		/// Take away internal buffer as if is its single immutable reference. This may change

        @property immutable(T)[] idup()
        {
			if (ptr_ is null)
				return null;
            return (ptr_)[0..length_].idup;
        }

        static if(!is(T == dchar))
        {
            /// encode append dchar to buffer as UTF Ts
            void put(dchar c)
            {
                static if (is(T==char))
                {
                    if (c < 0x80)
                    {
                        roomForExtra(1);
                        (ptr_)[length_++] = cast(char)c;
                        return;
                    }
                    T[4] encoded;
					if (c == 163)
					{
						c = 163;
					}
                    auto len = std.utf.encode(encoded, c);
					roomForExtra(len);
                    auto cptr = ptr_ + length_;
					length_ += len;
                    auto eptr = encoded.ptr;
                    while(len > 0)
                    {
						len--;
                        *cptr++ = *eptr++;
                    }

                }
                else static if (is(T==wchar))
                {
                    if (c < 0xD800)
                    {
						roomForExtra(1);
                        (ptr_)[length_++] = cast(wchar)c;
                        return;
                    }
                    else
                    {
                        T[2] encoded;
                        auto len = std.utf.encode(encoded, c);
						roomForExtra(len);
                        auto wptr = ptr_ + length_;
						length_ += len;
                        auto eptr = encoded.ptr;
                        while(len > 0)
                        {
							len--;
                            *wptr++ = *eptr++;
                        }

                    }
                }
            }
        }



        void opCatAssign(dchar c)
        {
            put(c);
        }

		int opApply(int delegate(dchar value) dg)
		{
			// let existing D code do it.
			if (ptr_ is null)
				return 0;
			auto slice = ptr_[0..length_];
			uintptr_t ix = 0;
			while (ix < slice.length)
			{
				dchar d = decode(slice,ix);
				auto result = dg(d);
				if (result)
					return result;
			}
			return 0;
		}

		/// Always allowed to append 0 at index of length_,
		void nullTerminate()
		{
			if (!ptr_)
			{
				// At least no one else owns this!
				length(0);
			}
			// always a space at the back
			(ptr_)[length_] = 0;
		}

		const(T)* cstr() @property
		{
			nullTerminate();
			return constPtr();
		}

    }
    static  if (is(T==char))
    {

        this(immutable(char)[] s)
        {
  			reserve(s.length);
			opCatAssign(s);
        }
		this(const(wchar)[] s)
		{
            reserve(s.length);
			opCatAssign(s);
		}
		this(const(dchar)[] s)
		{
			reserve(s.length);
			opCatAssign(s);
		}
        /// OpAssigns are opCatAssigns
        void  opAssign(const(wchar)[] s)
        {
			if (ptr_ !is null)
				length_ = 0;
            opCatAssign(s);
        }
        void  opAssign(const(dchar)[] s)
        {
			if (ptr_ !is null)
				length_ = 0;
            opCatAssign(s);
        }
		void put(const(wchar)[] s)
		{
			opCatAssign(s);
		}

        void opCatAssign(const(wchar)[] s)
        {
            immutable slen = s.length;
			if (slen==0)
				return;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen;)
            {
                wchar c = s[i];
                if (c > 0x7F)
                {
                    dchar d = decode(s, i);
                    put(d);
                }
                else
                {
                    i++;
					roomForExtra(1);
                    (ptr_)[length_++] = cast(char) c;
                }
            }
        }

        void opCatAssign(const(dchar)[] s)
        {
            immutable slen = s.length;
			if (slen==0)
				return;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen; i++)
            {
                dchar d = s[i];
                if (d > 0x7F)
                {
                    put(d);
                }
                else
                {
					roomForExtra(1);
                    (ptr_)[length_++] = cast(char)d;
                }
            }
        }
    }
	static if (is(T==wchar))
	{
		this(const(dchar)[] s)
		{
			reserve(s.length);
			opCatAssign(s);
		}
        void opCatAssign(const(dchar)[] s)
        {
            immutable slen = s.length;
			if (slen==0)
				return;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen; i++)
            {
                dchar d = s[i];
                if (d < 0x10000)
                {
					roomForExtra(1);
                    ptr_[length_++] = cast(char)d;
                }
                else
                {
					roomForExtra(2);
					size_t n = d - 0x10000;
					ptr_[length_++] = cast(wchar)(0xD800 + (n >> 10));
					ptr_[length_++] = cast(wchar)(0xDC00 + (n & 0x3FF));
                }
            }
        }
		this(const(char)[] s)
		{
			reserve(s.length);
			opCatAssign(s);
		}
        void opCatAssign(const(char)[] s)
        {
            immutable slen = s.length;
			if (slen==0)
				return;
			roomForExtra(slen);
			uintptr_t i = 0;
			while(i < slen)
			{
                dchar c = s[i++];

				if (c < 0x80)
				{
					roomForExtra(1);
					ptr_[length_++] = cast(char)c;
				}
				else if (c < 0xF0)
				{
					if (c < 0xC0)
					{
						throw new BufferError(format("invalid char {%x}", c));
					}
					roomForExtra(1);
					if (c < 0xE0 && i < slen)
					{
						c = c & 0x1F;
						c = (c << 6) + (s[i++] & 0x3F);
						ptr_[length_++] = cast(wchar)c;
					}
					else if (i < slen-1)
					{
						c = c & 0x0F;
						foreach(k;0..2)
							c = (c << 6) + (s[i++] & 0x3F);
						ptr_[length_++] = cast(wchar)c;
					}
				}
				else
				{	// 2 wchar
					roomForExtra(2);
					if (c < 0xF8 && i < slen-2)
					{
						c = c & 0x07;
						foreach(k;0..3)
							c = (c << 6) + (s[i++] & 0x3F);
					}
					if (c < 0xFC && i < slen-3)
					{
						c = c & 0x03;
						foreach(k;0..4)
							c = (c << 6) + (s[i++] & 0x3F);
					}
					size_t n = c - 0x10000;
					ptr_[length_++] = cast(wchar)(0xD800 + (n >> 10));
					ptr_[length_++] = cast(wchar)(0xDC00 + (n & 0x3FF));
				}
            }
        }
	}

	static  if (is(T==dchar))
    {
        /// OpAssigns are opCatAssigns
        void  opAssign(const(char)[] s)
        {
			if (ptr_ !is null)
			{
				length_ = 0;
			}
            opCatAssign(s);
        }
        void  opAssign(const(wchar)[] s)
        {
			if (ptr_ !is null)
			{
				length_ = 0;
			}
            opCatAssign(s);
        }

        void opCatAssign(const(char)[] s)
        {
            immutable   slen = s.length;
			if (slen==0)
				return;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen; )
            {
                dchar c = s[i];
                if (c > 0x7F)
                    c = decode(s, i);
                else
                    i++;
                roomForExtra(1);
                (ptr_)[length_++] = c;
            }
        }

        void opCatAssign(const(wchar)[] s)
        {
            immutable slen = s.length;
			if (slen==0)
				return;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen;)
            {
                dchar c = s[i];
                if (c > 0x7F)
                    c = decode(s,i);
                else
                    i++;
                roomForExtra(1);
                (ptr_)[length_++] = c;
            }
        }
    }

	T[] dup() @property
	{
		if (ptr_ is null)
			return null;
		return (ptr_)[0..length_].dup;
	}

	T[] takeArray()
	{
		if (ptr_ is null)
			return null;
		auto result = (ptr_)[0..length_];
		forget();
		return result;
	}
    const(T)[] slice(uintptr_t p1, uintptr_t p2)
    {
		assert((ptr_ !is null) && (p1 <= p2) && (p2 <= length_));
        return (ptr_)[p1..p2];
    }
    /// Get pointer to last value of internal buffer
    @property T* last()
    {
        if ((ptr_ is null) || length_ < 1)
            throw new BufferError("last: empty array");
        return ( ptr_ + (length_ - 1) );
    }

	@property bool empty() const {
		return (ptr_ is null) ? true : (length_ == 0);
	}
    /// append T[]
    void put(const(T)[] s)
    {
		if (s.length > 0)
			append(s.ptr, s.length);
    }
    /// Return  writeable slice of the buffer.
    T[] data() @property
    {
		if (!ptr_)
			return [];
		return  (ptr_)[0..length_];
    }
	bool opEquals( const(T)[] rhs) const
	{
		auto lhs = this.toConstArray();

		return typeid(T[]).equals(&rhs, &lhs);
	}
	bool opEquals(ref const ThisType ro) const
	{
		auto lhs = this.toConstArray();
		auto rhs = ro.toConstArray();

		return typeid(T[]).equals(&rhs, &lhs);
	}
    const(T)[] peek() const @property nothrow
    {
		if (ptr_ is null)
			return [];
		return ptr_[0..length_];
    }
	alias peek toConstArray;

	T[] take()
	{
		auto result = ptr_[0..length_];
		forget();
		return result;
	}

	int opCmp(ref const ThisType ro) const
	{

		auto lhs = this.toConstArray();
		auto rhs = ro.toConstArray();

		return typeid(T[]).compare(&lhs, &rhs);

	}
	/// sort in place
	/* static if (isSomeChar!T)
	{
	}
	else {
		const(T)[] sort() @property
		{
			if (ptr_ is null)
				return null;
			if(length_ <= 1)
				return (ptr_)[0..length_];
			T[] temp = (ptr_)[0..length_];
			if (length_ > 1)
			{
				std.algorithm.sorting.sort!("a < b")(temp);
			}
			return temp;
		}
	}
    */
	///
    T front()
    {
        if (ptr_ !is null)
		{
            if (length_ > 0)
				return  (ptr_)[0];
		}
		throw new BufferError("front: empty array");
    }
    ///
    T back()
    {
        if (ptr_ !is null)
		{
            if (length_  > 0)
				return  (ptr_)[length_-1];
		}
		throw new BufferError("back: empty array");
    }
	// create a new item on the end
	T* pushNew()
	{
		length = length_ + 1;
		return last();
	}

    void popBack()
    {
        if (ptr_ !is null)
		{
			auto blen = length_;
            if (blen > 0)
			{
				blen--;
				static if (!isScalarType!(T))
				{
				(ptr_)[blen] = T.init;
				}
				length_ = blen;
				return;
			}
		}
		throw new BufferError("movePopBack: empty array");
    }

    T movePopBack()
    {
        if (ptr_ !is null)
		{
			auto plength = &length_;
			auto blen = *plength;
            if (blen  > 0)
			{
				 blen--;
				 T* pdata = (ptr_) + blen;
				 auto result = *pdata;
				 static if (!isScalarType!(T))
				 {
					*pdata = T.init;
				 }
				 *plength = blen;
				 return result;
			}
		}
		throw new BufferError("movePopBack: empty array");
    }
    /// Equivalent to X.length = 0, as retains buffer and capacity
	/// Will wipe existing length to T.init regardless of type of T
    void reset()
    {
		if (!ptr_)
			return;

		if (length_ > 0)
		{
			destroy_data(ptr_,length_);
			length_ = 0;
		}
		length_ = 0;
	}


	/// define as within capacity or within length?
	bool isInside(const(T)* p) const
	{
		if (ptr_ is null)
			return false;
		else
		{
			return ((p >= ptr_) && (p < (ptr_ + capacity_ )));
		}
	}
	void append( const(T)* buf, uintptr_t slen)
	{
		if (slen == 0)
			return;
		if (ptr_ is null) {
			assign(buf, slen);
			return;
		}
		auto origlen = length_;
		auto newlen = origlen + slen;
		reserve(newlen);
		copy_create((ptr_) + origlen, buf, slen);
		length_ = newlen;
	}
	void opCatAssign(const(T) data)
	{
		append(&data, 1);
	}
	void opCatAssign(const(T)[] data)
	{
		append(data.ptr, data.length);
	}
	void opCatAssign(ref const ThisType tt)
	{
		append(tt.ptr_, tt.length_);
	}
	T opIndex(uintptr_t ix)
	{
		assert((ptr_ !is null) && (ix < length_));
		return (ptr_)[ix];
	}
	///
    void opIndexAssign(T value, uintptr_t ix)
    {
		assert((ptr_ !is null) && (ix < length_));
        (ptr_)[ix] = value;
    }

	/// remove any items equal to T.init, starting from pos;
	void pack(uintptr_t	pos = 0)
	{
		if (!ptr_ || length_ == 0)
			return;
		auto shrink = removeInit!T((ptr_)[0 .. length_], pos);
		length_ -= shrink;
	}

	/// Avoid multiple bitblits because of this(this)
	this(this)
	{
		if (ptr_)
		{
			auto tempPtr = ptr_;
			auto tempLength = length_;
			ptr_ = null;
			length_ = 0;
			capacity_ = 0;
			assign(tempPtr, tempLength);
		}
	}
	/** This leads to GC collect exceptions, so clean up elsewhere
	~this()
	{
		if (ptr_)
		{
			shrinkTo(0);
			freeCapacity(ptr_,true);
		}
	}
	*/

	T* ptr_;
	uintptr_t	length_;
	uintptr_t	capacity_;
}

unittest
{
	Buffer!int	test;

	auto len = test.length;
}


/**
Allocator purpose is to amortize  memory and time overhead
of allocating strings which are copied from mutable sources, an alternative to using idup.

Second parameter results in append of zero character, so .ptr property will be a C null-terminated string.

This is a trade-off.
Testing showed it used about 70% of memory and about 30% of the time, compared to using idup on char[].
Disadvantage for the Garbage Collector is the resulting strings will behave like slices of one big string.
The whole block will be freed only when all its slices are found not referenced by pointer.
This includes Alloc struct itself, which will be pointing to the last chunk acquired.

This is ideal for where this happens anyway, such that all the strings are part of one document,
or all are temporaries created during processing, such that all are likely to be forgotten at once.

Clients of such documents, in long running applications, should be mindful that retaining a few random pointers
to these allocated strings may incur a bigger memory overhead, if they do not take care to duplicate.

The allocator gets a big chunk from the Garbage Collector, and chops off an aligned block for
each string allocated. The allocator itself cannot track or reclaim allocated strings. When the
remaining block is too small, it is forgotten and replaced by a new chunk.

Savings get less as average string length increases, compared to chunk capacity. Default Chunk is 8192 bytes.


**/


struct ImmuteAlloc(T,bool NullEnd = false)
{
private:
    size_t	capacity_ = 0;
    size_t	length_ = 0;
    T*		ptr_ = null;
    size_t	totalAlloc_ = 0; // statistics
public:
    enum { DefaultSliceBlock  = 8192 / T.sizeof };

    this(size_t cap)
    {
        fresh(cap);
    }

    //
    void fresh(size_t cap)
    {
            auto bi = GC.qalloc(cap * T.sizeof,  (typeid(T[]).next.flags & 1) ? 0 : GC.BlkAttr.NO_SCAN);
            ptr_ = cast(T*) bi.base;
            immutable al = bi.size;
            totalAlloc_ += al;
            capacity_ = al / T.sizeof;
            length_ = 0;
    }

    immutable(T)[] alloc(const(T)[] orig)
    {

		debug(NOALLOC) {
			auto result = to!(immutable(T)[])(orig);

		}
		else {
        immutable slen = orig.length;

        size_t alen = slen;
		static if (NullEnd)
			alen++;

        if ((alen & alignMask) > 0)
        {
            alen = (alen & alignData) + alignBits;   // zero last 2 bits, add 4
        }
        if (alen + length_ > capacity_)
        {
            if (capacity_ == 0)
                capacity_ = DefaultSliceBlock;

            if (alen > capacity_)
            {
                fresh(alen);
            }
            fresh(capacity_);
        }
        memcpy(ptr_, orig.ptr, slen * T.sizeof);
		static if (NullEnd)
			ptr_[slen] = 0;

        immutable(T)[] result = (cast(immutable(T)*)ptr_)[0..slen];
        ptr_ += alen;
        length_ += alen;
		}

        return result;
    }

    @property size_t totalAlloc()
    {
        return totalAlloc_;
    }

}


/** Store a sequence of temporary character strings in a single buffer.
	The string starts are not memory aligned.
	The lengths (end points) are stored as an offset in a seperate buffer to permit random access.
	The indexed values are always still locatable after memory reallocation, whereas storing
	slices of the values array would become invalid.
	Appending and random access by integer index work well.
	Rewrites and removals will not be supported, apart from a
	general reset from scratch. The buffer is intended to be frequently re-used,
	and grows to the maximum size required.

	ends[length1, length1 + length2, length1 + length2 + length3, ...
*/

struct PackedArray(T)
{

    Buffer!T		     values;
    Buffer!int			 ends;

    @property size_t length() const
    {
        return ends.length;
    }
    void opCatAssign(const (T)[] data)
    {
        auto extent = values.length;
        values.put(data);
        ends.put(cast(int)(data.length+extent));
    }

    // set lengths to zero without sacrificing current buffer capacity.
    void reset()
    {
        values.length = 0;
        ends.length = 0;
    }

    /**
    Retrieve the indexed array as a transient value.

    */

    const(T)[] opIndex(size_t ix)
    {
        auto slen = ends.length;

        if (ix >= slen)
             BufferError.makeIndexError(ix);

        auto endLength = ends[ix];
        auto startLength = (ix > 0) ? ends[ix-1] : 0;
        return values.slice(startLength, endLength);
    }
    /**
    	Index match to value
    */
    int indexOf(const(T)[] match)
    {
        auto slen = ends.length;
        if (slen == 0)
            return -1;
        T[] contents = values.toArray;
        auto spos = 0;
        auto epos = 0;
        for(auto i = 0; i < slen; i++)
        {
            epos = ends[i];
            if (match == contents[spos..epos])
                return i;
            epos = spos;
        }
        return -1;
    }
    /** Create array pointing to each individual array.
    	At some point the contents will be overwritten.
    */
    const(T)[][] transient()
    {
        auto slen = ends.length;
        const(T)[][] result = new const(T)[][slen];
        if (slen == 0)
        {
            reset();
            return result;
        }
        T[] contents = values.toArray;
        size_t spos = 0;
        size_t epos = 0;
        for(size_t i = 0; i < slen; i++)
        {
            epos = ends[i];
            result[i] = contents[spos..epos];
            spos = epos;
        }
        return result;
    }
    /** Use a single array to create a whole set of immutable sub-arrays at once.
      The disadvantage will be that for any to be Garbage Collected, all individual arrays
      must be un-referenced. This also resets the original collection
    */
    immutable(T)[][] idup()
    {
        auto slen = ends.length;
        immutable(T)[][] result = new immutable(T)[][slen];
        if (slen == 0)
        {
            return result;
        }
        immutable(T)[] contents = values.idup;
        size_t spos = 0;
        size_t epos = 0;
        for(size_t i = 0; i < slen; i++)
        {
            epos = ends[i];
            result[i] = contents[spos..epos];
            spos = epos;
        }
        reset();
        return result;
    }

    // similar, except use given storage and calfing allocator
    immutable(T)[][] idup(immutable(T)[][] result, ref ImmuteAlloc!(T) strAlloc)
    {
        auto slen = ends.length;
        if (slen == 0)
        {
            reset(); // keep consistant
            return result;
        }
        auto contents = values.toArray;
        size_t spos = 0;
        size_t epos = 0;
        for(size_t i = 0; i < slen; i++)
        {
            epos = ends[i];
            result[i] = strAlloc.alloc(contents[spos..epos]);
            spos = epos;
        }
        reset();
        return result;
    }

}


/// Element of sortable array of pairs on key
struct KeyValRec(K,V)
{
	alias KeyValRec!(K,V) SameType;

    K id;
    V value;

	bool opEquals(ref const SameType ro) const
	{
		return (this.id==ro.id) && (this.value==ro.value);
	}
	const int opCmp(ref const SameType s)
	{
		return typeid(K).compare(&id, &s.id);
	}
}

/**
	Store pairs of values, possible keyed, in a record array as a struct.

	The AUTOSORT template parameter, adds a binary sort on the key member.
	When using this, to avoid automatic resort with opIndexAssign, either
	call the put method directly, which will flag the need for a sort,
	but just appends to the end, or set the deferSort property, which will have
the same effect in calling opIndexAssign.
	Otherwise, opIndexAssign will call indexOf, which checks the sorted property,
	and will do a sort, prior to a binary search to find the index.
	Whether key duplicates matter or not, is up to the programmer.

*/



