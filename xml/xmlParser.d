module xml.xmlParser;

import std.stdint;
import xml.xmlChar, std.variant, std.string, std.conv, std.utf, std.traits;
import xml.txml, xml.xmlAttribute, xml.xmlError, xml.textInput, xml.util.read;
import xml.dom.dtdt;
import std.path, std.stream, std.range;
import std.format;
import xml.util.gcstats;
import xml.util.buffer;
import xml.util.bomstring;

version = ParseDocType;

alias bool delegate(ref const(dchar)[] buf) MoreInputDg; // For a stream datasource
private enum BBCount { b1, b2, bend };

/// It is hard to separate the parser from concrete data structures of a DOM
/// but possible because the basic XML structure is regular
/// In particular, clustered complexities like a DTD require intricate and specific object relationships
/// with special rules. The idea of EntityData, 
/// or reuseable segments of XML which are specified in a DTD, is particularly
/// an implementation headache.

class XmlParser(T)  {

	alias XmlParser!(T) ThisType;

    version(GC_STATS)
    {
        mixin GC_statistics;
        static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
    }
	private {
		bool				validate_;
		bool				isStandalone_;
		bool				namespaceAware_;
		bool				normalizeAttributes_;
		bool				inDTD_;
		bool				isEntity;
		bool				hasDeclaration;
		bool				hasXmlVersion;
		bool				hasStandalone;
		bool				hasEncoding;
		bool				slicing_; // current data source is immutable slice
		bool				deviantData_; // sliced data run was broken
		bool				inCharData;
		bool				eventMode_; // results by events
		BBCount				bbct;
	}

	Object getInstance()
	{
		return this;
	}
	
	alias xmlt!T.XmlString  XmlString;
	alias xmlt!T.XmlBuffer	XmlBuffer;


	alias XMLDTD!(T).EntityData EntityData;
	alias XMLDTD!(T).DocTypeData DocTypeData;
	alias XMLDTD!(T).StringSet StringSet;
	alias XMLDTD!(T).ExternalID ExternalID;
	alias XMLAttribute!T.XmlAttribute	Attribute;
	alias xmlt!T.IXmlDocHandler			IXmlDocHandler;
	alias xmlt!T.IXmlErrorHandler		IXmlErrorHandler;
	alias xmlt!T.AttributeMap           AttributeMap;
	alias xmlt!T.XmlEvent				XmlEvent;

	alias void delegate() ParseStateDg;

	static struct MarkSlice {
		immutable(T)*	ptr_;
		debug immutable(T)*	 		viewptr_;
		uintptr_t		start_;
		uintptr_t		end_;

		void start(immutable(T)* p, uintptr_t pos)
		{
			ptr_ = p;
			debug viewptr_ = p + pos;
			start_ = pos;
			end_ = 0;
		}
		void end(immutable(T)* p, uintptr_t pos)
		{
			assert(ptr_ == p && pos >= start_);
			end_ = pos;
		}
		immutable(T)[] opSlice() const
		{
			assert((ptr_ !is null) && (start_ <= end_));
			return ptr_[start_..end_];
		}
	}

	static struct XmlContext
	{
		int					markupDepth;
		int					elementDepth;
		int					squareDepth;
		int					parenDepth;
		int					docDeclare;
		dchar				front = 0;
		bool				empty  = true;

		double				docVersion_;
		
		//Buffer!dchar		backStack;	 // oops wrong way buffer
		dchar[]				backStack_;
		// a single block of unparsed xml
		uintptr_t			mpos;		 // start char index of front for slicing
		bool				slicing;	 // current context is sliceData_
		immutable(T)[]		sliceData;		 // current input buffer
		const(dchar)[]		streamData;	// dynamic stream data

		MoreInputDg			inputDg_;		// more stream data
		uintptr_t			fpos;		 // position in buffer
		EntityData			entity;
		bool				scopePop;
		size_t				lineNumber_;
		size_t				lineChar_;
		dchar				lastChar_;
		bool				isEndOfLine_;
		bool				minVersion11_;
		CharFilter			doFilter_;



		this(EntityData ed = null, bool doPop = false)
		{
			entity = ed;
			scopePop = doPop;
		}


	}

    enum PState
    {
        P_PROLOG, // default, initial state
        P_INT_DTD,
		P_DATA,
        P_EPILOG,
        P_END
    }
	void explode()
	{
	    fillSource_ = null;
	    events_ = null;
	    errors_ = null;
	}


	private
	{
		ParseStateDg	stateDg_;

		final void unpop(string s)
		{
			foreach_reverse(char c ; s)
				unpop(c);
		}


		string getSourceContext()
		{
			if (slicing_)
			{
				auto backPos = sliceData_.length;
				if (backPos > 0)
				{
					auto frontPos = (fpos > 20) ? fpos - 20 : 0;
					if (backPos > fpos + 20)
						backPos = fpos + 20;
					return format("%s [ %s ] %s", sliceData_[frontPos..fpos], front, sliceData_[fpos..backPos]);
				}

			}
			else {
				auto backPos = streamData_.length;
				if (backPos > 0)
				{
					auto frontPos = (fpos > 20) ? fpos - 20 : 0;
					if (backPos > fpos + 20)
						backPos = fpos + 20;
					return format("%s [ %s ] %s", streamData_[frontPos..fpos], front, streamData_[fpos..backPos]);
				}
			}
			return "";
		}
		// handle finished XmlDataSoource
		private bool sourceDone(XmlDataSource ds)
		{
			if (!slicing_)
			{
				streamData_ = null;
				ds.explode();
				inputDg_ = null;
			}
			return false;
		}
		class XmlDataSource {
			const(T)[]  source_;
			SliceFill!T	translator_;
			ulong		pos_;

			this(const(T)[] src)
			{
				source_ = src;
				translator_ = new SliceFill!T(src);
			}

			void explode()
			{
				delete translator_;
				source_ = null;
				pos_ = 0;
			}

			bool getData(ref const(dchar)[] buf)
			{
				if (translator_.fillData(buf,pos_))
					return true;
				return this.outer.sourceDone(this);
			}
		}
		// unconditional stuff back
		private void pushBack(dchar c)
		{
			if (!empty)
				backStack ~= front;
			front = c;
			empty = false;
		}
		private void unpopMalfunction()
		{
			throw errors_.makeException("parser malfunction on unpop");
		}
		final void unpop(dchar makeFront)
		{
			if ((backStack.length > 0) || !slicing_)
			{
				// already stacked, regardless of source
				if (!empty)
					backStack ~= front;
				front = makeFront;
				empty = false;
				return;
			}
			if (slicing_)
			{
				// Assume exact reverse with check for character
				
				if (mpos > 0)
				{
					fpos = mpos;
					static if (is(T==char)) {
						while (true)
						{
							if (fpos == 0)
								unpopMalfunction();
							fpos--;
							if ((sliceData_[fpos] & 0xC0) != 0x80)
								break; // found a start character
						}
					}
					else static if (is(T==wchar)) {
						while (true)
						{
							if (fpos == 0)
								unpopMalfunction();
							fpos--;
							dchar w16 = sliceData_[fpos];
							if (w16 < 0xD800 || w16 >= 0xE000) 
								break; // as-is character
							// its a surrogate pair, so needs to be two of them
							if (fpos == 0)
								unpopMalfunction();
							fpos--;
							w16 = sliceData_[fpos];
							if (w16 >= 0xD800 && w16 < 0xE000) 
								break; // ready for decode
							unpopMalfunction();
						}
					}
					else static if (is(T==dchar)) {
						if (fpos == 0)
							unpopMalfunction();
						fpos--;
					}
				}
				else {
					if (fpos == 0)
						unpopMalfunction();
					fpos = 0;
				}
				mpos = fpos;
				// confirm
				dchar test = decode(sliceData_,fpos);
				assert(makeFront == test);
				front = makeFront;
				empty = false;
				return;
				
			} // working through dchar[] 
			else if (( fpos > 0) && (fpos <= streamData_.length) && (streamData_[fpos-1]==front))
			{
				fpos--;
				mpos--;
				front = makeFront;
				empty = false;
				return;
			}
			// out of matching front space
			if (!empty)
				backStack ~= front;
			front = makeFront;
			empty = false;
			return;

		}
		final void popFront()
		{
			if (!empty)
			{
				auto bslen = backStack.length;
				if (bslen > 0)
				{
					bslen--;
					front = backStack[bslen];
					backStack.length = bslen;
					return;
				}
				if (slicing_)
				{
					if (fpos >= sliceData_.length)
					{
						if (inCharData) // bolognaise
						{
							mpos = sliceData_.length;
							returnTextContent();
						}
						while(true)
						{
							if ((contextStack_.length > 0) && !this.scopePop)
							{
								sliceData_ = null;
								popContext();
								if (!empty)
									return; // front was previously accounted for.
								else
									continue;
							}
							empty = true;
							return;
						}
					}
					mpos = fpos;
					front = decode(sliceData_,fpos);
				}
				else {
					if (fpos >= streamData_.length)
					{
						while (true)
						{
							if (inputDg_ && inputDg_(streamData_))
							{
								fpos = 0;
								break;
							}
							else {
								streamData_ = null;
							}

							if ((contextStack_.length > 0) && !this.scopePop)
							{
								popContext();
								if (!empty)
									return; // front was previously accounted for.
								else
									continue;
							}
							empty = true;
							return;
						}
					}
					front = streamData_[fpos++];
				}

				if (doFilter_ != CharFilter.filterOn)
					lineChar_++;
				else
					filterFront();
				return;
			}
		}
		final void filterFront()
		{

			immutable c = front;
			if (isEndOfLine_)
			{
				isEndOfLine_ = false;
				lineNumber_++;
				lineChar_ = 0;
				if (lastChar_ == 0x0D)
				{	// filter 0x0D, XXXX combinations
					lastChar_ = 0;
					if (c==0x0A)
					{
						popFront();
						return;
					}
					else if (minVersion11_)
					{
						if (c==0x85)
						{
							popFront();
							return;
						}
						else if (c==0x2028)
						{
							front = 0x0A;
							return;
						}
					}
				}
				lastChar_ = 0;
			}
			if ((c >= 0x20) && (c < 0x7F))
			{
				lineChar_++;
				return;
			}
			else
			{ // detect endOfLine or crazy characters
				switch(c)
				{
					case 0x0D:
						lastChar_ = 0x0D;
						front = 0x0A;
						goto case 0x0A;
					case 0x0A:
						isEndOfLine_ = true;
						break;
					case 0x09:
						lineChar_++;
						break;
					case 0x0085:
					case 0x2028:
						if (minVersion11_)
						{
							lastChar_ = c;
							front = 0x0A;
							isEndOfLine_ = true;
						}
						else
						{
							lineChar_++;
						}
						break;
					default:
						// already approved 0x9, 0xA, 0xD,  0x20 - 0x7F, 0x85
						immutable isSourceCharacter
							=   (c <= 0xD7FF) 
							?  (c > 0x9F) || ((filterVersion_==1) && (c >= 0x20))
							: ((c >= 0xE000) && (c <= 0xFFFD)) || ((c >= 0x10000) && (c <= 0x10FFFF)) ;
							

						if (!isSourceCharacter)
						{
							auto severity = XmlErrorLevel.FATAL;
							// Check position for crappy check for conformance tests on invalid BOM characters.
							if (lineChar_ == 0 && lineNumber_ == 0)
								switch(front)
								{
									case 0xFFFE:
									case 0xFEFF:
										severity = XmlErrorLevel.ERROR;
										goto default;
									default:
										break;
								}
							throw errors_.makeException(badCharMsg(front),severity);
						}
						lineChar_++;
						break;
				}

			}
		}
		final void frontFilterOn()
		{
			if ((doFilter_ != CharFilter.filterOff) || empty)
				return;
			if (lineChar_ != 0)
				lineChar_--; // filter front will increment for current front
			doFilter_ = CharFilter.filterOn;
			filterFront();
		}

			/// stop any calls to frontFilterOn and frontFilterOff from working. Always off
		final void filterAlwaysOff()
		{
			doFilter_ = CharFilter.filterAlwaysOff;
		}

		/// Turn the filter off
		final void frontFilterOff()
		{
			if (doFilter_ != CharFilter.filterAlwaysOff)
				doFilter_ = CharFilter.filterOff;
		}


		// The entire parser , uses a popFront after recognition policy.
		// No need to popFront, to check a character match, then unpop it again if not matching
		// This causes some issues to handle for Entity context push and pop.
		//
		// eat matching input or restore
		final bool matchInput(dchar val)
		{
			if (!empty && front == val)
			{
				popFront();
				return true;
			}
			return false;
		}
		// Eat matching input or restore. can only match if char < 0x80
		final bool matchInput(string match)
		{
			if (empty)
				return false;
			size_t lastmatch = 0; // track number of matched
			size_t mlen = match.length;
			char[]	bufMatch;

			for( ; lastmatch < mlen; lastmatch++)
			{
				if (empty)
					break;
				if (front != match[lastmatch])
					break;
				bufMatch ~= cast(char)(front & 0x7F);
				popFront();
			}
			if (lastmatch == 0)
				return false;
			else if (lastmatch == mlen)
				return true;
			else
			{
				foreach_reverse(d;bufMatch)
					unpop(d);
				return false;
			}
		}
		/// got a '[', check the rest
		final bool isCDataEnd()
		{
			if (empty || front != ']')
				return false;


			squareDepth--;
			popFront();
			if (empty || front != ']')
			{
				unpop(']');
				squareDepth++;
				return false;
			}

			squareDepth--;
			popFront();
			if (empty || front != '>')
			{
				unpop("]]");
				squareDepth += 2;
				return false;
			}
			markupDepth--;
			popFront();
			return true;
		}

		alias immutable(T)[] StringType;
		// Mark source slice positions. Easily invalidated by context change.
		int					stackElementDepth;
		// .. Start Working context .. Accessed via direct this
		int					markupDepth;
		int					elementDepth;
		int					squareDepth;
		int					parenDepth;
		int					docDeclare;

		double				docVersion_ = 1.0;  // what this document is
		double				parentVersion_ = 0.0;  // if an entity, version of calling document
		double				filterVersion_ = 1.0;  // the resulting filter standard

		// set if won't allow a newer version

		dchar				front = 0;
		bool				empty  = true;

		//Buffer!dchar		backStack;	 // oops wrong way buffer
		dchar[]				backStack;
		MarkSlice			marker_;
		uintptr_t			mpos;
		immutable(T)[]		sliceData_;		 // current input buffer

		const(dchar)[]		streamData_;
		MoreInputDg			inputDg_;
		uintptr_t			fpos;
		EntityData			entity;
		bool				scopePop;

		CharFilter			doFilter_;

		size_t				lineNumber_;
		size_t				lineChar_;
		dchar				lastChar_;
		bool				isEndOfLine_;
		bool				minVersion11_;
		//.. End Working context

		XmlCharTypeFn		isNameStartFn;
		XmlCharTypeFn		isNameCharFn;
		IXmlErrorHandler		errors_;
		IXmlDocHandler			events_;

		PState					state_;

		string[]			systemPaths_;
		//double				XMLVersion;
		intptr_t			maxEdition;


		immutable(T)[]			tag_;	// used by doStartTag
		immutable(T)[]			attrName_;
		immutable(T)[]			attrValue_;

		//Buffer!T				bufNormAttr_;
		//Buffer!T				bufAttr_;
		//Buffer!T				bufTag_;
		//Buffer!T				bufEndTag_;
		//Buffer!T				bufMatch_;
		//Buffer!T				bufContent_;
		// Buffers

		XmlBuffer 	bufNormAttr_, bufAttr_, bufTag_, bufEndTag_,bufMatch_, bufContent_;
		
		AttributeMap     		attributes_;
		XmlEvent     		    results_;

		StringType[StringType]	charEntity;
		XmlContext[]     	contextStack_;
		XmlString[]         entityStack_;

		DocTypeData			dtd_;
		intptr_t			itemCount;
		uintptr_t			attributeCount;

		// manage own primary source
		BufferFill!(dchar)	fillSource_;
		ulong				fillPos_;
		int					bomMark_;
		// introduced for the DOCTYPE
		//ImmuteAlloc!(T,true)	stringAlloc_;

		bool fillData(ref const(dchar)[] data)
		{
			return fillSource_.fillData(data,fillPos_);
		}

		/// assign a dchar buffer filling primary source
		public void fillSource(BufferFill!dchar src) @property
		{
			fillSource_ = src;
			initSource(&fillData);
		}
		// read the data in a block, translate if necessary to T.
		public void sliceFile(string srcPath)
		{
			auto s = readTextBom!T(srcPath,bomMark_);
			auto xml = (cast(immutable(T)*) s.ptr)[0..s.length];
			addSystemPath(normalizedDirName(srcPath));
			initSource(xml);
		}

		// called from doXmlDeclaration
		void setXmlVersion(double value)
		{
			// Tricky. If 
			
			if ((value != 1.0) && (value != 1.1))
			{
				uint major = cast(uint) value;
				if (major != 1 || maxEdition < 5)
					throw errors_.makeException(format("XML version %s not supported ",value),XmlErrorLevel.ERROR);
			}
			docVersion_ = value;
			if (isEntity)
			{
				if (docVersion_ > parentVersion_)
					throw errors_.makeException(format("Entity version %s > Document version %s", docVersion_, parentVersion_), XmlErrorLevel.FATAL);
				filterVersion_ = parentVersion_;
			}
			else 
				filterVersion_ = docVersion_;
			
			minVersion11_ = (filterVersion_ > 1.0);

			if (minVersion11_)
			{
				isNameStartFn = &isNameStartChar11;
				isNameCharFn = &isNameChar11;
			}
		}




		final bool isNameStartFifthEdition(dchar test)
		{
			if (docVersion_ == 1.0 && maxEdition >= 5)
			{
				if (!isNameStartChar11(test))
					return false;

				if (validate_)
				{
					errors_.pushError("Name start character only specified by XML 1.0 fifth edition",XmlErrorLevel.INVALID);
					errors_.checkErrorStatus();
				}
				return true;
			}
			return false;
		}
		final bool isNameCharFifthEdition(dchar test)
		{
			if (docVersion_ == 1.0 && maxEdition >= 5)
			{
				if (!isNameChar11(test))
					return false;

				if (validate_)
				{
					errors_.pushError("Name character only specified by XML 1.0 fifth edition",XmlErrorLevel.INVALID);
					errors_.checkErrorStatus();
				}
				return true;
			}
			return false;
		}
		
		final bool getXmlName(ref XmlBuffer ename)
		{
			if (empty)
				return false;
			auto test = front;
			if ( !(isNameStartFn(test) || isNameStartFifthEdition(test)) )
				return false;

			frontFilterOff();
			//ename.length = 0;
			ename.shrinkTo(0);
			ename ~= test;
			popFront();
			while (!empty)
			{
				test = front;
				if (isNameCharFn(test) || isNameCharFifthEdition(test))
				{
					ename ~= test;
					popFront();
				}
				else
					break;
			}
			frontFilterOn();
			return true;
		}
		// The returned string may be a slice or created from buffer by idup
		final bool getXmlName(ref XmlString tag)
		{
			if (empty)
				return false;
			auto test = front;
			if ( !(isNameStartFn(test) || isNameStartFifthEdition(test)) )
				return false;

			frontFilterOff();
			if (slicing_)
			{
				marker_.start(sliceData_.ptr,mpos);
			}
			/// Slicing fails on last character in slice and pop of context on empty
			/// So have to buffer collect anyway
			//bufTag_.length = 0;
			bufTag_.shrinkTo(0);
			bufTag_ ~= test;

			popFront();
			while (!empty)
			{
				test = front;
				if (isNameCharFn(test) || isNameCharFifthEdition(test))
				{
					bufTag_ ~= test;
					popFront();
				}
				else
					break;
			}
			if (slicing_)
			{
				marker_.end(sliceData_.ptr,mpos);
				tag = marker_[];
			}
			else {
				//tag = bufTag_.idup;
				tag = bufTag_.data.idup;
			}
			frontFilterOn();
			return true;
		}

		final void getAttributeValue(ref immutable(T)[] val)
		{
			munchSpace();
			dchar test;
			if (empty || (front != '='))
				throw errors_.makeException(XmlErrorCode.EXPECTED_ATTRIBUTE);
			popFront();
			munchSpace();
			unquoteValue(val);
		}
		final void unquoteValue(ref XmlString val)
		{
			dchar enquote = (empty ? 0x00 : front);
			bool  deviant = false;

			if ((enquote != '\'') && (enquote != '\"'))
			{
				throw errors_.makeException(XmlErrorCode.MISSING_QUOTE);
			}
			popFront();
			if (slicing_)
			{
				marker_.start(sliceData_.ptr, mpos);
			}

			//bufAttr_.length = 0;
			bufAttr_.shrinkTo(0);
			frontFilterOn();
			while(!empty)
			{
				if (front == enquote)
				{
					if (bufAttr_.data.length > 0)
					{
						if (slicing_ && !deviant)
						{
							marker_.end(sliceData_.ptr, mpos);
							val = marker_[];
						}
						else {
							val = bufAttr_.data.idup;
						}
					}
					else
						val = [];
					frontFilterOff();
					popFront();
					return;
				}
				else
				{
					if (lastChar_)
						deviant = true;
					bufAttr_ ~= front;
					popFront();
				}
			}
			throw errors_.makeException(XmlErrorCode.MISSING_QUOTE);
		}

		final uint munchSpace()
		{
			int   count = 0;
			while(!empty)
			{
				switch(front)
				{
					case 0x20:
					case 0x0A:
					case 0x09:
					case 0x0D: // may be introduced as character reference
						count++;
						popFront();
						break;
					default:
						return count;
				}
			}
			return 0;
		}

		/// must be after a <?
		void doProcessingInstruction(uint spaceCt = 0)
		{
			immutable(T)[] target;

			if (!getXmlName(target))
				throw errors_.makeException("Bad processing instruction name");

			if (namespaceAware_ && (indexOf(target,':') >= 0))
				throw errors_.makeException(format(": in process instruction name %s for namespace aware parse",target));

			if (target == "xml")
			{
				if (inDTD_)
					throw errors_.makeException("Xml declaration may not be in DTD");
				if (state_ != PState.P_PROLOG || (spaceCt > 0) || (itemCount > 0))
					throw errors_.makeException("xml declaration should be first");
				if (!hasDeclaration)
				{
					hasDeclaration = true;
					try
					{
						doXmlDeclaration();
						munchSpace();
						return;
					}
					catch (XmlError xm)
					{
						throw errors_.caughtException(xm, xm.level);
					}
					catch (Exception ex)
					{
						throw errors_.caughtException(ex);
					}
				}
				else
					throw errors_.makeException("Duplicate xml declaration");
			}
			auto lcase = target.toLower();

			if (lcase == "xml")
			{
				throw errors_.makeException(format("%s is invalid name", target));
			}

			getPIData(bufContent_);

				//XmlEvent!T	results_;
			with (results_)
			{
				eventId = XmlResult.XML_PI;
				data = target;
				attributes = Attribute(target,bufContent_.data.idup);
			}
			if(eventMode_)
				events_.instruction(results_);

			itemCount++;
			if (state_ == PState.P_PROLOG)
				munchSpace();
		}

		final void getPIData(ref XmlBuffer app)
		{
			dchar  test  = 0;

			bool	hasContent = false;
			bool	hasSpace = false;
			app.shrinkTo(0);

			frontFilterOn();
			while(!empty)
			{
				test = front;
				popFront();
				if (test=='?')
				{
					if (!empty && front=='>')
					{
						markupDepth--;
						popFront();
						break;
					}
				}
				if (!hasContent)
				{
					if (isSpace(test))
						hasSpace = true;
					else
					{
						hasContent = true;
						app ~= test;
					}
				}
				else
					app ~= test;
			}
			if (hasContent && !hasSpace)
				throw errors_.makeException("Processing instruction needs space after name");
		}


		Exception makeEmpty()
		{
			return errors_.makeException(XmlErrorCode.UNEXPECTED_END);
		}
		void doProlog()
		{
			int spaceCt = 0;
			frontFilterOn();
			LOOP_FOREVER:
			while(!empty)
			{
				spaceCt = munchSpace();

				if (empty)
					break;

				if (front == '<')
				{
					markupDepth++;
					frontFilterOff();
					popFront();
					if (empty)
						throw makeEmpty();
					auto test = front;
					switch(test)
					{
						case '?':
							popFront();
							doProcessingInstruction(spaceCt);
							break;
						case '!':
							popFront();
							if (matchInput("DOCTYPE"))
							{
								doDocType();
								break;
							}
							else if (matchInput("--"))
							{
								// valid-sa-038  , but if followed by XML declaration its an error!
							    itemCount++;
								doCommentContent();
								break;
							}
							else
								throw errors_.makeException("Illegal in prolog");
							//goto default;
						default:
							if (getXmlName(tag_))
							{
								if (!hasDeclaration)
								{
									if (validate_)
									{
										errors_.pushError("No xml declaration",XmlErrorLevel.INVALID);
									}
								}
								elementDepth++;
								state_ = PState.P_DATA; // into the document proper
								stateDg_ = &doContent;
								doStartTag();
								return;
							}
							else {
								throw errors_.makeException(badCharMsg(test));
							}
							//break;

					} // end switch
					if (!eventMode_)
						return; // with event
				} // end peek
				else
				{
					throw errors_.makeException("expect xml markup");
				}
				// else?
			} // end while
			throw errors_.makeException("bad xml");
			assert(0);
		}


		double doXmlVersion(const(T)[] xmlversion)
		{
			T[]  scratch;

			NumberClass nc = parseNumber(ReadRange!T(xmlversion), scratch);

			//auto vstr = scratch_.toArray;
			if (nc != NumberClass.NUM_REAL)
				throw errors_.makeException(format("xml version %s weird ",xmlversion));
			if (scratch.length < xmlversion.length)
				throw errors_.makeException("additional text in xml version");
			return  to!double(scratch);
		}
		// After getting '<!--' leave in bufContent_
		final void parseComment()
		{
			dchar  test  = 0;
			if (slicing_)
			{
				deviantData_ = false;
				marker_.start(sliceData_.ptr, mpos);
			}
			bufContent_.shrinkTo(0);
			frontFilterOn();
			while(!empty)
			{
				if (front=='-')
				{
					popFront();
					if (empty)
						break;
					if (front=='-')
					{
						if (slicing_ && !deviantData_)
							marker_.end(sliceData_.ptr,mpos-1);
						popFront();
						if (empty)
							break;
						if(front != '>')
							throw errors_.makeException("Comment must not contain --");
						markupDepth--;
						popFront();
						return;
					}
					bufContent_ ~= '-';
					continue;
				}
				bufContent_ ~= front;
				popFront();
			}
			throw errors_.makeException("Unterminated comment");
		}
		final void doCommentContent()
		{
			parseComment();
			with(results_)
			{
				eventId = XmlResult.COMMENT;
				if (slicing_ && !deviantData_)
					data = marker_[];
				else
					data = bufContent_.data.idup;
				attributes.reset();
			}
			if (eventMode_)
				events_.comment(results_);
			bufContent_.shrinkTo(0);

		}

		final void checkEndElement()
		{
			int depth =  elementDepth + stackElementDepth;
			if (depth < 0)
				throw errors_.makeException(XmlErrorCode.ELEMENT_NESTING);
			else if (depth == 0)
			{
				stateDg_ = &doEpilog;
				state_ = PState.P_EPILOG;
			} // else?
			if (elementDepth < 0)
				throw errors_.makeException(XmlErrorCode.ELEMENT_NESTING);
		}
		void doXmlDeclaration()
		{
			double xml_value = 1.0;
			immutable(T)[] xmlStrValue;
			immutable(T)[] encodingValue;
			immutable(T)[] standaloneValue;

			//state_ = XML_DECLARATION;
			int spaceCt =  munchSpace();
			size_t atcount = 0;
			isStandalone_ = false; // if has an xml declaration, assume false as default
			//string atname;
			//string atvalue;

			void xmlVersionFirst(bool force=false)
			{
				if (!isEntity || force)
					errors_.pushError("xml version must be first",XmlErrorLevel.FATAL);
			}

			void xmlDuplicate(const(T)[] s)
			{
				errors_.pushError(format("duplicate %s", s),XmlErrorLevel.FATAL);
			}
			void xmlStandaloneLast()
			{
				errors_.pushError("xml standalone must be last",XmlErrorLevel.FATAL);
			}


			// get the values before processing

			while(!matchInput("?>"))
			{
				if (!getXmlName(attrName_))
				{
					//throwNotWellFormed("declaration attribute expected");
					// got a strange character?
					if (empty)
						throw makeEmpty();
					dchar badChar = front;
					//Extreme focus on XML declaration conformance errors.
					switch(badChar)
					{
						case '>':
						case '<':
							throw errors_.makeException("expected ?>");
							//break;
						case '\'':
						case '\"':
							throw errors_.makeException("expected attribute name");
							//break;
						case 0x85:
						case 0x2028:
							if (xml_value == 1.1)
							{
								errors_.pushError(format("%x illegal in declaration", badChar),XmlErrorLevel.ERROR);
								errors_.checkErrorStatus();
							}
							goto default;
						default:
							throw errors_.makeException(badCharMsg( badChar));
					}
				}


				if  (!spaceCt)
					throw errors_.makeException("missing spaces");

				getAttributeValue(attrValue_);
				if (attrName_.length==0)
					throw errors_.makeException("empty declaration value");

				atcount += 1;

				switch(attrName_)
				{
					case "version":
						if (hasXmlVersion)
						{
							xmlDuplicate(attrName_);
							break;
						}
						if (hasStandalone || hasEncoding)
							xmlVersionFirst(true);
						hasXmlVersion = true;
						xmlStrValue = attrValue_;
						xml_value = doXmlVersion(xmlStrValue);
						break;
					case "encoding":
						if (!hasXmlVersion)
							xmlVersionFirst();
						if (hasStandalone)
							xmlStandaloneLast();
						if (hasEncoding)
						{
							xmlDuplicate(attrName_);
							break;
						}
						encodingValue = to!(immutable(T)[]) (attrValue_);
						hasEncoding = true;
						break;
					case "standalone":
						if (isEntity)
							throw errors_.makeException("standalone illegal in external entity");
						if (!hasXmlVersion)
							xmlVersionFirst();
						if (hasStandalone)
						{
							xmlDuplicate(attrName_);
							break;
						}
						standaloneValue = attrValue_;
						hasStandalone = true;
						break;
					default:
						throw errors_.makeException(format("unknown declaration attribute %s ", attrName_));
						//break;
				}
				spaceCt = munchSpace();
			}
			attributes_.reset();

			if (hasXmlVersion)
			{
				setXmlVersion(xml_value);
				attributes_.push(Attribute("version",xmlStrValue));
			}
			markupDepth--;
			if (isEntity && !hasEncoding)
				throw errors_.makeException("Optional entity text declaration must have encoding=");
			errors_.checkErrorStatus();

			if (hasEncoding)
			{
				setXmlEncoding(encodingValue);
				attributes_.push(Attribute("encoding", encodingValue));
			}
			if (hasStandalone)
			{
				setXmlStandalone(standaloneValue);
				attributes_.push(Attribute("standalone", standaloneValue));
			}
			// send event
			with(results_)
			{
				eventId = XmlResult.XML_DEC;
				data = "xml";
				attributes = attributes_;
			}
			if (eventMode_)
				events_.declaration(results_);

			//TODO: Event call
			state_ = PState.P_DATA;
			stateDg_ = &doContent;
			itemCount++;
		}

		/// Chicken and egg. Start off by not knowing encoding, except by BOM
		/// After reading coding declaration, may need to change the source processing.
		/// Do by events call back?  Throw and catch own exception?
		void setXmlEncoding(const(T)[] encoding)
		{
			bool encodingOK = (encoding.length > 0) && isAlphabetChar(encoding[0]);
			if (encodingOK)
			{
				encodingOK = isAsciiName!(const(T)[])(encoding);
			}
			if (!encodingOK)
			{
				throw errors_.makeException(format("Bad encoding name: %s", encoding));
			}
			// prepare to fail low level
			try
			{
				// encoding stuff in dchar ?
				errors_.setEncoding(encoding);
				if (fillSource_)
					fillSource_.setEncoding(to!string(encoding));
			}
			catch (XmlError ex)
			{
				// defer
				switch(ex.level)
				{
					case XmlErrorLevel.INVALID:
						// convert to report and carry on
						if (validate_)
						{
							errors_.pushError(ex.toString(),XmlErrorLevel.INVALID);
						}
						break; // ignore
					case XmlErrorLevel.ERROR:
						errors_.pushError(ex.toString(),XmlErrorLevel.ERROR);
						break;
					case XmlErrorLevel.FATAL:
					default:
						errors_.pushError(ex.toString(),XmlErrorLevel.FATAL);

				}
			}
			catch(Exception ex)
			{
				errors_.pushError(ex.toString(),XmlErrorLevel.FATAL);
			}
			errors_.checkErrorStatus();
			//dataFiller_.setBufferSize(SRC_BUF_SIZE);
		}
		void setXmlStandalone(const(T)[] standalone)
		{
			if (standalone == "yes")
				isStandalone_ = true;
			else if (standalone == "no")
				isStandalone_ = false;
			else
				throw errors_.makeException(format("Bad standalone value: %s",standalone));
		}
		/// already got a '</' and put it back expecting a Name>
		final void doEndTag()
		{
			state_ = PState.P_DATA;
			dchar  test;
			if (getXmlName(tag_))
			{
				// has to be end
				munchSpace();
				if (empty || front != '>')
					throw errors_.makeException(XmlErrorCode.MISSING_END_BRACKET);
				markupDepth--;
				elementDepth--;
				popFront();
				checkEndElement();
				itemCount++;
				with(results_)
				{
					eventId = XmlResult.TAG_END;
					data = tag_;
					attributes.reset();
				}
				if (eventMode_)
					events_.endTag(results_);
				return;
			}
			throw errors_.makeException("end tag expected");
		}
		// called if getXmlName(bufTag_)
		final void doStartTag()
		{
			int attSpaceCt = 0;
			auto attrCount = 0;
			attributes_.reset();

			//auto prepareAttributes = (evt_.nameEvent.startTagDg_ !is null) || (evt_.nameEvent.soloTagDg_ !is null);
			void setResults(XmlResult id)
			{
				with(results_)
				{
					eventId = id;
					data = tag_;
					attributes = attributes_;
				}

				if (eventMode_)
				{
					if (id == XmlResult.TAG_START)
						events_.startTag(results_);
					else
						events_.soloTag(results_);
				}
			}

			while (true)
			{
				attSpaceCt = munchSpace();

				if (empty)
					throw makeEmpty();

				switch(front)
				{
					case '>': // end of tag,  possible inner content
						markupDepth--;
						frontFilterOn();
						if (elementDepth + stackElementDepth == 1) // very first tag
						{
							// delayed popFront,
							// processing as startTag
							setResults(XmlResult.TAG_START);
							popFront();
							return;
						}

						popFront();

						if (empty)
							throw makeEmpty();
						/* Check for immediate following end tag, which means TAG_EMPTY */
						if (front == '<')
						{
							/*NoneEmptyState nes;
							getState(nes);*/
							markupDepth++;

							// regression ticket 7: popping front here, because want to check if next character is a / using a strict input range
							// to check the dchar
							popFront();
							if (empty)
								throw makeEmpty();
							if (front == '/')
							{
								// by strict rules of XML, must be the end tag of preceding start tag.
								popFront();
								if (empty)
									throw makeEmpty();
								if (!getXmlName(attrName_) || (tag_ != attrName_))
									throw errors_.makeException(XmlErrorCode.ELEMENT_NESTING);
								munchSpace(); // possible space after end tag name!
								if (empty || (front != '>'))
									throw errors_.makeException(XmlErrorCode.MISSING_END_BRACKET);
								markupDepth--;
								elementDepth--; // cancel earlier increment
								popFront();
								setResults(XmlResult.TAG_EMPTY);
								checkEndElement();
								itemCount++;
								return;
							}
							else
							{
								markupDepth--;
								unpop('<');
								setResults(XmlResult.TAG_START);
							}
							return;
						}
						itemCount++;
						setResults(XmlResult.TAG_START);
						return;
					case '/':
						popFront();
						if (empty)
							throw makeEmpty();
						if (front != '>')
							throw errors_.makeException(XmlErrorCode.TAG_FORMAT);
						markupDepth--;
						elementDepth--;
						frontFilterOn();
						popFront();
						setResults(XmlResult.TAG_EMPTY);
						checkEndElement();
						itemCount++;
						return;

					default:
						// processs another attribute
						if (attSpaceCt == 0)
						{
							throw errors_.makeException(XmlErrorCode.MISSING_SPACE);
						}
						if (!getXmlName(attrName_))
						{
							errors_.pushError(getXmlErrorMsg(XmlErrorCode.EXPECTED_ATTRIBUTE),XmlErrorLevel.INVALID);
							throw errors_.makeException(badCharMsg(front));
						}

						if (attSpaceCt == 0)
							throw errors_.makeException(XmlErrorCode.MISSING_SPACE);

						getAttributeValue(attrValue_);


						if (normalizeAttributes_)
						{
							attributeNormalize(attrValue_);

							if (attrName_ == "xml:space")
							{
								if (attrValue_ == "preserve")
								{

								}
								else if (attrValue_ == "default")
								{

								}
								else
								{
									errors_.makeException("xml:space must equal 'preserve' or 'default'",XmlErrorLevel.ERROR);
								}
							}
							/// TODO: actually implement space instructions?



						}
						attributes_.push(Attribute(attrName_,attrValue_));

						attrCount += 1;
						break;
				}
			}
			assert(0);
		}

		void returnTextContent()
		{
			// encountered non-content character, return content block
			itemCount++;
			with(results_)
			{
				eventId = XmlResult.TEXT;
				if (slicing_ && !deviantData_)
				{
					marker_.end(sliceData_.ptr, mpos);
					data = marker_[];
				}
				else {
					data = bufContent_.data.idup;
				}
				attributes.reset();
			}
			if (eventMode_)
				events_.text(results_);
			//bufContent_.length = 0;
			bufContent_.shrinkTo(0);
			inCharData = false;
			deviantData_ = false;
			return;
		}

		final void doContent()
		{
			bufContent_.shrinkTo(0);
			inCharData = false;
			frontFilterOn();
			LOOP_FOREVER:
			while (true)
			{	// loop until something new occurs
				if (empty)
				{
					if (elementDepth + stackElementDepth > 0)
						throw makeEmpty();
					if (inCharData)
						returnTextContent();
					return;
				}
				if (front == '<')
				{
					if (inCharData)
					{
						returnTextContent();
						if (!eventMode_)
							return;
					}
					markupDepth++;
					frontFilterOff();
					popFront();
					if (empty)
						throw makeEmpty();
					auto test = front;
					switch(test)
					{
						case '/':
							popFront();
							doEndTag();
							if (state_ == PState.P_EPILOG)
								return;
							break;
						case '?':
							popFront();
							doProcessingInstruction();
							break;
						case '!': // comment or cdata
							popFront();
							doBang();
							break;
						default:
							// no pop front
							if (getXmlName(tag_))
							{
								elementDepth++;
								doStartTag();
								break;
							}
							else
							{
								/// trick conformance issue
								errors_.pushError(getXmlErrorMsg(XmlErrorCode.TAG_FORMAT),XmlErrorLevel.FATAL);
								throw errors_.makeException(badCharMsg(test));
							}
					} // end switch
					if (eventMode_)
						continue LOOP_FOREVER;
					else
						return;
				}
				else if (front=='&')
				{
					if(!deviantData_)
					{
						deviantData_ = true;
						//returnTextContent();
					}
					// Cannot determine content in advance. Invalidates content so far, ? return text so far?
					popFront();
					if (!empty)
					{
						uint radix;
						if (front == '#')
						{
							dchar test = expectedCharRef(radix);
							bufContent_ ~= test;
							inCharData = true;
							continue;
						}
						else if (getXmlName(tag_))
						{
							if (empty || front != ';')
								throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
							popFront();
							auto pc = tag_ in charEntity;
							if (pc !is null)
							{
								bufContent_ ~= *pc;
								inCharData = true;
								continue;
							}
							if (!pushEntity(tag_, false))
							{
								/// Generate character data, then Entity, then proceed again with content.
								/// This requires an event stack, if call model is to be kept
								if (inCharData)
								{
									entityStack_.put(tag_); // store for next call
									returnTextContent(); // return content so far
								}
								else {
									// entity Name event
									if (eventMode_)
										events_.entityName(tag_,false);
								}
								if (eventMode_)
									continue;
								else
									return;

							}
							continue;
						}
					}
					errors_.makeException("expected entity");
				}
				else
				{
					if (!inCharData)
					{
						inCharData = true;
						bufContent_.shrinkTo(0);
						if (slicing_)
						{
							marker_.start(sliceData_.ptr, mpos);
							deviantData_ = false;
						}
					}
					if (lastChar_)
						deviantData_ = true;
					bufContent_ ~= front;
					final switch(bbct)
					{
					case BBCount.b1:
						if (front==']') bbct = BBCount.b2;
						break;
					case BBCount.b2:
						bbct = (front==']') ? BBCount.bend : BBCount.b1;
						break;
					case BBCount.bend:
						if (front=='>')
							throw errors_.makeException("illegal CDATA end ]]>");
						bbct = (front==']') ? BBCount.bend : BBCount.b1;
						break;
					}

					popFront();

				} // end switch
			} // While not epilog
		}
		final void doEpilog()
		{
			dchar test = 0;
			string content;

			LOOP_FOREVER:
			while(!empty)
			{
				munchSpace();
				if (empty)
					break;
				if (front != '<')
				{
					throw errors_.makeException("illegal data at end document");
				}

				markupDepth++;

				popFront();
				if (empty)
					throw errors_.makeException("unmatched markup");
				switch(front)
				{
					case '?': // processing instruction or xmldecl
						popFront();
						doProcessingInstruction(); // what else to do with PI'S?
						break;
						//break LOOP_FOREVER;
					case '!':
						if (empty)
							throw makeEmpty();
						popFront();
						if (matchInput("--"))
						{
							doCommentContent();
							break;
						}
						goto default;
					default:
						if (getXmlName(bufTag_))
							throw errors_.makeException(format("Epilog illegal %s",bufTag_.data),XmlErrorLevel.FATAL);
						else
							throw errors_.makeException("Epilog illegal " ~ badCharMsg(front));
				}
			}
			with (results_)
			{
				eventId = XmlResult.DOC_END;
				data = null;
				attributes.reset();
			}
			state_ = PState.P_END;
			stateDg_ = null;
		}

		/** got a <! and put it back */
		final void doBang()
		{
			if (matchInput("[CDATA["))
			{
				squareDepth += 2;
				doCDATAContent();
				return;
			}
			else if (matchInput("--"))
			{
				doCommentContent();
				return;
			}
			throw errors_.makeException(XmlErrorCode.CDATA_COMMENT);
		}

		final void doCDATAContent()
		{
			bufContent_.shrinkTo(0);
			if (slicing_)
			{
				marker_.start(sliceData_.ptr, mpos);
				deviantData_ = false;
			}
			frontFilterOn();
			while(!empty)
			{
				if ((front == ']') && isCDataEnd())
				{
					if (slicing_ && !deviantData_)
					{
						marker_.end(sliceData_.ptr,mpos-3);
					}
					itemCount++;
					with(results_)
					{
						eventId = XmlResult.CDATA;
						if (slicing_ && !deviantData_)
						{
							data = marker_[];
						}
						else
							data = bufContent_.data.idup;
						attributes.reset();
					}
					if (eventMode_)
						events_.cdata(results_);
					bufContent_.shrinkTo(0);
					return;
				}
				else
				{
					if (slicing_ && lastChar_)
						deviantData_ = true;
					bufContent_ ~= front;
					popFront();
				}
			}
			throw makeEmpty();
		}

		final dchar expectedCharRef(ref uint radix)
		{
			if (empty)
				throw makeEmpty();
			if (front != '#')
				throw errors_.makeException(badCharMsg(front));
			popFront();
			dchar result;
			radix = refToChar(result);

			if (
				((docVersion_ < 1.1) && !isChar10(result)) ||
				(!isChar11(result) && !isControlCharRef11(result))
			)
			{
				throw errors_.makeException(badCharMsg(front));
			}
			return result;
		}
		/// Return value is the radix of the encoding for the character
		/// Throws exception for invalid encoding
		final uint refToChar(ref dchar c)
		{
			dchar test;
			int digits = 0;
			uint radix = 10;

			if (empty)
				throw makeEmpty();

			test = front;

			if (test == 'x')
			{
				popFront();

				radix = 16;
				if (empty)
					throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
				test = front;
			}
			int 	n = 0;
			ulong	value = 0; // 64 bits, detect 32 bit overflow

			while(test == '0')
			{
				popFront();
				if (empty)
					throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
				test = front;
			}
			if (radix == 10)
			{
				while(true)
				{
					if (( test >= '0') && ( test <= '9'))
					{
						n = (test - '0');
						value *= 10;
						value += n;
						digits++;
					}
					else
						break; // not part of number

					popFront();
					if (empty)
						throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
					if (value > 0x10FFFF)
						throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
					test = front;
				}
			}
			else
			{
				while(true)
				{
					if (( test <= '9') && (test >= '0'))
						n = (test - '0');
					else if ((test <= 'F') && (test >= 'A'))
						n = (test - 'A') + 10;
					else if ((test <= 'f') && (test >= 'a'))
						n = (test - 'a') + 10;
					else
						break;// not part of number
					digits++;
					value *= 16;
					value += n;

					popFront();
					if (empty)
						throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
					if (value > 0x10FFFF)
						throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
					test =  front;
				}
			}
			if (test != ';')
			{
				throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
			}
			popFront();
			c = cast(dchar) value;
			return radix;
		}
	}// end private {

	/// IXMLParser
	bool inDTD()
	{
		return inDTD_;
	}

	DocTypeData DTD()
	{
		return dtd_;
	}

    bool  inParamEntity() const @property
    {
        return (entity !is null) && (entity.etype_ == EntityType.Parameter);
    }

    ///  IXMLParser method, may not actually be used
    bool inGeneralEntity() const @property
    {
        return (entity !is null) && (entity.etype_ == EntityType.General);
    }

    ///   IXMLParser method, may not actually be used
    XmlString getEntityName()
    {
        return entity !is null ? entity.name_ : null;
    }

    ///   IXMLParser method, may not actually be used
    @property EntityData entityContext()
    {
        return entity;
    }

    /// property
    @property void entityContext(EntityData val)
    {
        entity = val;
    }
    /// property
    @property bool isInternalContext()
    {
        return (entity is null) || (entity.isInternal_);
    }

	@property double xmlVersion() const {
		return filterVersion_;
	}
    void setParameter(string name, Variant n)
    {
		switch(name)
		{
			case xmlAttributeNormalize:
				normalizeAttributes_ = n.get!bool;
				break;
			case xmlNamespaces:
				namespaceAware_ = n.get!bool;
				break;
			case xmlCharFilter:
				if (n.get!bool == false)
				{
					filterAlwaysOff();
				}
				break;
			case "edition":
				{
					maxEdition = n.get!uint;
				}
				break;
			default:
				break;
		}
    }
	void addSystemPath(string dir)
	{
		systemPaths_ ~= dir;
	}
	version(GC_STATS)
	{
        ~this()
        {
            gcStatsSum.dec();
        }
	}

	this()
	{
		version(GC_STATS)
			gcStatsSum.inc();

		stateDg_ = &doProlog;
		setEntityValue("lt","<");
		setEntityValue("gt",">");
		setEntityValue("amp","&");
		setEntityValue("quot","\"");
		setEntityValue("apos","\'");
		isNameStartFn = &isNameStartChar10;
		isNameCharFn = &isNameChar10;
		normalizeAttributes_ = true;
		isStandalone_ = true;
		results_ = new XmlEvent();
		setXmlVersion(1.0);
	}

	@property {
		intptr_t tagDepth() const
		{
			return stackElementDepth + elementDepth;
		}
		final void eventReturn(XmlEvent ret)
		{
			results_ = ret;
		}
		final XmlEvent eventReturn()
		{
			return results_;
		}
		final void docInterface(IXmlDocHandler pdata)
		{
			events_ = pdata;
		}
		final void errorInterface(IXmlErrorHandler pdata)
		{
			errors_ = pdata;
		}
	}

	final void setErrorHandler(IXmlErrorHandler pdata)
	{
		errors_ = pdata;
	}
	
	@property IXmlErrorHandler errorHandler()
	{
		return errors_;
	}

	final void initSource(immutable(T)[] src)
	{
		sliceData_ = src;
		mpos = 0;
		fpos = 0;
		slicing_ = true;
		empty = (sliceData_.length==0);
		popFront();
	}
	final void initSource(MoreInputDg dg)
	{
		inputDg_ = dg;
		empty = false;
		popFront();
	}
	final void parseAll(XmlEvent evt = null)
	{
		eventMode_ = true;
		if (evt !is null)
			results_ = evt;

		while(stateDg_ !is null)
		{
			stateDg_();
		}
	}

	/// do single event and return
	void parseOne()
	{
		eventMode_ = false;
		stateDg_();
	}

	///IXMLParser
    void popContext()
    {
		if (!scopePop)
			checkBalanced();
        auto slen = contextStack_.length;
        if (slen > 0)
        {
            slen--;
			auto ctx_ = contextStack_[slen];

			markupDepth += ctx_.markupDepth;
			elementDepth += ctx_.elementDepth;
			squareDepth += ctx_.squareDepth;
			parenDepth += ctx_.parenDepth;

			if (inParamEntity)
			{
				docDeclare += ctx_.docDeclare;
			}
			else {
				stackElementDepth -= elementDepth;
			}

			inputDg_ = ctx_.inputDg_;


			mpos = ctx_.mpos;
			deviantData_ = true; // flag a context escape/loss

			front = ctx_.front;
			empty = ctx_.empty;
			docVersion_ = ctx_.docVersion_;
			backStack = ctx_.backStack_;	 // oops wrong way buffer
			sliceData_ = ctx_.sliceData;		 // current input buffer
			streamData_ = ctx_.streamData;
			slicing_ = ctx_.slicing;

			fpos = ctx_.fpos;
			entity = ctx_.entity;
			scopePop = ctx_.scopePop;
			lineNumber_ = ctx_.lineNumber_;
			lineChar_ = ctx_.lineChar_;
			lastChar_ = ctx_.lastChar_;
			isEndOfLine_ = ctx_.isEndOfLine_;
			minVersion11_ = ctx_.minVersion11_;

			doFilter_ = ctx_.doFilter_;
			contextStack_.length = slen;
        }
		if (slen==0)
			stackElementDepth = 0;
    }
    void getLocation(ref SourceRef sref)
    {
        sref.charsOffset = 0;
        sref.lineNumber = lineNumber_;
        sref.colNumber = lineChar_;
    }
    /// push a new context, for parse, maybe with EntityData
    void pushContext()
	{
		auto cix = contextStack_.length;
		contextStack_.length = cix + 1;

		XmlContext* ctx_ = &contextStack_[cix];

		ctx_.markupDepth = markupDepth;
		ctx_.elementDepth = elementDepth;
		ctx_.squareDepth = squareDepth;
		ctx_.parenDepth = parenDepth;
		ctx_.docDeclare = docDeclare;
		ctx_.inputDg_ = inputDg_;
		ctx_.mpos = mpos;
		ctx_.front = front;
		ctx_.empty = empty;
		ctx_.docVersion_ = docVersion_;
		ctx_.backStack_ = backStack;
		ctx_.sliceData = sliceData_;		 // current input buffer
		ctx_.streamData = streamData_;
		ctx_.slicing = slicing_;
		ctx_.fpos = fpos;

		ctx_.entity = entity;
		ctx_.scopePop = scopePop;
		ctx_.lineNumber_ = lineNumber_;
		ctx_.lineChar_ = lineChar_;
		ctx_.lastChar_ = lastChar_;
		ctx_.isEndOfLine_ = isEndOfLine_;
		ctx_.minVersion11_ = minVersion11_;

		ctx_.doFilter_ = doFilter_;

		// setup new defaults
		lineNumber_ = 0;
		lineChar_ = 0;
		lastChar_ = 0;
		isEndOfLine_ = false;

		fpos = 0;
		mpos = 0;
		streamData_ = null;
		sliceData_ = null;
		slicing_ = false;

        markupDepth = 0;
		stackElementDepth += elementDepth;
        elementDepth = 0;
        squareDepth = 0;
        parenDepth = 0;
		docDeclare = 0;
		// doFilter_ retains value
		deviantData_ = true; // flag a context escape/loss
		backStack = [];
		empty = false;
		// force new front

	}

    void pushContext(immutable(T)[] data, bool inScope = true, EntityData edata = null)
	{
		pushContext();
		sliceData_ = data;
		slicing_ = true;
		entity = edata;
		scopePop = inScope;

		if (inScope || edata !is null)
            filterAlwaysOff();

		popFront();
	}

    bool pushEntity(const(T)[] ename, bool isAttribute)
    {
        EntityData ed = getEntityData(ename, isAttribute);

        if (ed !is null)
        {
            auto evalue = ed.value_;
            if (evalue.length > 0)
			{
				//frontFilterOff();
                pushContext(evalue,false,ed);
			}
			return true;
        }
		else 
			errors_.checkErrorStatus();
		return false;
    }

    EntityData getEntityData(const(T)[] dname, bool isAttribute)
    {
        if (dtd_ is null)
            throw makeUnknownEntity(dname);

        auto ge = dtd_.getEntity(dname);

        if (ge is null)
        {
            if (dtd_.undeclaredInvalid_ && !isAttribute)
            {
                if (validate_ )
                {
                    errors_.pushError(format("referenced undeclared entity %s", dname),XmlErrorLevel.INVALID);
                    errors_.checkErrorStatus();
                }
                return null;
            }
            else
                throw makeUnknownEntity(dname);
        }
        if (ge.status_ == EntityData.Expanded)
            return ge;

		if (isAttribute)
			if (ge.src_.systemId_.length > 0)
				throw errors_.makeException("Entity with System reference in attribute");
        StringSet eset;

        int reftype = RefTagType.UNKNOWN_REF;
		if (! deriveEntityContent(ge, eset, reftype))
            return null;
		/*
        if (!lookupReference(ge.name_, eset, value, reftype))
        {
            doNotWellFormed(text("Error in entity lookup: ", ge.name_));
        }
		*/

        if (reftype==RefTagType.NOTATION_REF)
        {
            throw errors_.makeException(text("Reference to unparsed entity ",dname));
        }
        /*if(isAttribute && this.isStandalone_ && reftype==RefTagType.SYSTEM_REF)
            throw errors_.makeException("External entity in attribute of standalone document");*/

        return ge;
	}

    Exception makeUnknownEntity(const(T)[] dname)
    {
        string s = format("Unknown entity %s", dname);
        auto level = inParamEntity()  ? XmlErrorLevel.ERROR : XmlErrorLevel.FATAL;

        return errors_.makeException(s,level);
    }



	bool isNmToken(const(T)[] dval)
    {
        if(dval.length == 0)
            return false;
        uintptr_t ix = 0;
        while(ix < dval.length)
        {
            if (!isNameCharFn(decode(dval,ix)))
                return false;
        }
        return true;
    }
    /// return true if entire name is XML name
    bool isXmlName(const(T)[] dval)
    {
        if(dval.length == 0)
            return false;
        uintptr_t ix = 0;
        dchar test = decode(dval, ix);
        if (!isNameStartFn(test) || isNameStartFifthEdition(test))
            return false;
        while (ix < dval.length)
        {
            test = decode(dval, ix);
            if (!isNameCharFn(test) || isNameCharFifthEdition(test))
                return false;
            if (test == ':' && namespaceAware_)
                return false;
        }
        return true;
    }


	void setEntityValue(StringType entityName, StringType value)
	{
		charEntity[entityName] = value;
	}

    bool validate() const @property
    {
        return validate_;
    }
    void validate(bool val) @property
    {
        validate_ = val;
    }
    bool isStandalone() const
    {
        return isStandalone_;
    }
    bool namespaces() const
    {
        return namespaceAware_;
    }
    void namespaces(bool doNamespaces)
    {
        namespaceAware_ = doNamespaces;
    }
    /// Read from current input context, replacing character references
    protected bool doReplaceCharRef(ref XmlBuffer app)
    {
        dchar rchar = 0;
		auto beginLength = app.data.length;

        while (!empty)
        {
			immutable test = front;
            if (test == '&')
            {
                //startStackID_ = stackID_;
                popFront();
                if (empty)
                    throw makeEmpty();
                if (front == '#')
                {
                    popFront();
                    refToChar(rchar);
                    app ~= rchar;
                }
                else
                {
                    // process the entity name
					immutable(T)[] entityName;
                    app ~= '&';
                    if (!getXmlName(entityName) || !matchInput(';'))
						throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
                    app ~= entityName;
                    app ~= ';';
                }
            }
            else
            {
                app ~= test;
                popFront();
            }
        }
        return (app.data.length - beginLength > 0);
    }
	/// return entity data object
    EntityData getParameterEntity(const(T)[] peName, ref StringSet stk, bool isValue = true)
    {
        EntityData pe = dtd_.getEntity(peName,true);

        if (pe is null)
        {
            return null;
        }

        if (pe.status_ < EntityData.Expanded)
        {
			// expand by replacing its internal entities recursively
            if (!stk.put(peName))
            {
                errors_.pushError(format("Recursion for entity: %s ",peName),XmlErrorLevel.ERROR);
                return null;
            }
            if (pe.status_ == EntityData.Unknown)
            {
                auto sys_uri = to!string(pe.src_.systemId_);

                if ((sys_uri is null) || (sys_uri.length == 0))
                {
                    errors_.pushError("no system reference for entity",XmlErrorLevel.FATAL);
                    return null;
                }
				if (!readSystemEntity(pe))
					return null;
                //Document doc = new Document();
                /*if (!.getSystemEntity(vp, sys_uri, srcput, baseDir))
                {
                    errors_.pushError("resolve system reference failure", XmlErrorLevel.FATAL);
                    return null;
                }
				pe.isInternal_ = false;
                pe.baseDir_ = baseDir;
                pe.value_ = srcput;
                pe.status_ = EntityData.Found;
				*/

            }
            if (pe.value_.length > 0)
            {
                XmlBuffer	buf1;

                {
					this.pushContext(to!(immutable(T)[])(pe.value_));
					scope(exit)
						this.popContext();
                    if (!doReplaceCharRef(buf1))
                    {
                        errors_.pushError("bad char references",XmlErrorLevel.FATAL);
                        return null;
                    }
                }
                if (isValue)
                {
					this.pushContext(buf1.data.idup);
					scope(exit)
						this.popContext();
					buf1.shrinkTo(0);
                    expandParameterEntities(pe.isInternal_, buf1, stk);
                }
                pe.value(buf1.data.idup);
            }
            pe.status_ = EntityData.Expanded;
            stk.remove(peName);
        }
        return pe;
    }
	//textReplaceEntities.  Throws exceptions on error
	void expandParameterEntities(bool isInternal, ref XmlBuffer app, ref StringSet stk)
    {
        XmlString evalue;
		//app.clear();// caller has responsibility

        while (!empty)
        {
            switch(front)
            {
				case '%':
					popFront();
					{
						if (!empty && isNameStartFn(front))
						{
							immutable(T)[] entityName;
							if (!getXmlName(entityName) || !matchInput(';'))
								throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
							EntityData ed = getParameterEntity(entityName,stk,true);
							if (ed is null)
								throw errors_.makeException(format("Parameter entity %s not found", entityName));
							app ~= ed.value_;
						}
					}
					break;
				default:
					app ~= front;
					popFront();
					break;
            }

        }
        return;
    }
    /// recursively replace entities in the pushed context till empty
	/// return false if no replacement done
    bool attributeTextReplace(ref XmlBuffer app, uint callct = 0)
    {
		bool result = false; // flag if whitespace replace or entity expansion
	NEXT_CHAR:
        while(!empty)
        {
			immutable test = front;
			switch(test)
			{
				case 0x20:
				case 0x0D:
				case 0x0A:
				case 0x09:
					app ~= cast(char)0x20;
					if (0x20 != test)
						result = true;
					popFront();
					continue NEXT_CHAR;
				case '<':
					throw errors_.makeException("< not allowed in attribute value");
					//break;

				case '&':
					popFront();
					if (empty)
						throw errors_.makeException("single '&' not allowed");
					result = true;
					if (front == '#')
					{
						uint radix;
						dchar cref = expectedCharRef(radix);
						app ~= cref;
						continue NEXT_CHAR;
					}
					XmlString entityName;

					if (!getXmlName(entityName) || !matchInput(';'))
						throw errors_.makeException("single '&' not allowed");

					auto pc = entityName in charEntity;
					if (pc !is null)
					{
						app ~= *pc;
					}
					else
					{
						string evalue;
						EntityData ed = getEntityData(entityName, true);
						if (ed !is null)
						{
							if (!ed.isInternal_ && this.isStandalone_)
								throw errors_.makeException(format("External entity %s referenced from standalone",entityName));
							this.pushContext(to!(immutable(T)[])(ed.value_));
							scope(exit)
								this.popContext();
							attributeTextReplace(app, callct+1);
						}
						else
						{
							// TODO: put the reference again? exception
							errors_.checkErrorStatus();
						}
					}
					break;
				default:
					app ~= test;
					popFront();
					break;
			}//switch
        }
		return result;
    }

	void attributeNormalize(ref immutable(T)[] src)
    {
        //TODO: any other standard entities not allowed either?
        void noLTChar()
        {
            throw errors_.makeException("< not allowed in attribute value");
        }

        void noSingleAmp()
        {
			throw errors_.makeException("single '&' not allowed");
        }

		intptr_t   epos = -1;
	ENTITY_SCAN:
		for(auto ix = 0; ix < src.length; ix++)
		{
			switch(src[ix])
			{
				case '<':
					noLTChar();
					break;
				case '&':
					epos = ix;
					break ENTITY_SCAN;
				default:
					break;
			}
		}
		if (epos < 0)
		{
			// no entities
			return;
		}
		bufNormAttr_.shrinkTo(0);
		bufNormAttr_ ~= src[0..epos];
        pushContext(src[epos..$], true, null);
        scope(exit)
            popContext();

        SCAN:
		while(!empty)
        {
			immutable test = front;
			switch(test)
			{
			case 0x20:
			case 0x0D:
			case 0x0A:
			case 0x09:
				bufNormAttr_ ~= ' ';
                popFront();
                continue SCAN;
			case '<':
				noLTChar();
				break;
			case '&':
                popFront();
                if (empty)
                    noSingleAmp();
                if (front == '#')
                {
                    uint radix;
                    dchar cref = expectedCharRef(radix);
                    bufNormAttr_ ~= cref;
                    continue;
                }
				XmlString entityName;
                if (!getXmlName(entityName) || !matchInput(';'))
                    noSingleAmp();
                auto pc = entityName in charEntity;
                if (pc is null)
                {
                    pushEntity(entityName, true);
                }
                else
                {
                    bufNormAttr_ ~= *pc;
                }
				break;
			default:
                bufNormAttr_ ~= front;
                popFront();
				break;
            }
        }
		src = bufNormAttr_.data.idup;
    }


	version(ParseDocType)
	{
		// Read the specification of external entity PUBLIC, SYSTEM or just SYSTEM
		alias XMLDTD!(T).ExternalDTD ExternalDTD;
		alias XMLDTD!(T).ElementDef ElementDef;
		alias XMLDTD!(T).AttributeDef AttributeDef;
		alias XMLDTD!(T).AttributeList AttributeList;
		alias XMLDTD!(T).ChildElemList ChildElemList;
		alias XMLDTD!(T).ChildId ChildId;

		enum DocEndType { noDocEnd, singleDocEnd, 	doubleDocEnd };

		private bool getSystemLiteral(ref XmlString opt)
		{
			if (empty)
				throw makeEmpty();

			if ((front == '\"') || (front == '\''))
			{
				unquoteValue(opt);
				if (opt.length == 0)
				{
					return true;
				}
				//throwNotWellFormed("Empty SYSTEM value");
			}
			else
			{
				return false;
			}
			if (opt.indexOf('#') >= 0)
				throw errors_.makeException("SYSTEM URI with fragment '#'",XmlErrorLevel.ERROR);
			return true;
		}

		private bool getExternalUri(ref ExternalID ext)
		{
			ExternalID result;
			int spacect;

			bool doSystem()
			{
				spacect = munchSpace();
				XmlString opt;

				if (getSystemLiteral(opt))
				{
					if (spacect == 0)
						throw errors_.makeException("Need space before SYSTEM uri");
					if (opt.length == 0)
						ext.systemId_ = "";
					else
						ext.systemId_ = opt;
					return true;
				}
				return false;
			}

			if (matchInput("PUBLIC"))
			{
				spacect = munchSpace();
				XmlString opt;
				if (!getPublicLiteral(opt))
					throw errors_.makeException("Expected a PUBLIC name");
				if (spacect == 0)
					throw errors_.makeException("Need space before PUBLIC name");
				doSystem();
				ext.publicId_ = opt;
				return true;
			}
			else if (matchInput("SYSTEM"))
			{
				doSystem();
				return true;
				//if (!doSystem()) return false;
			}
			return false;
		}
		private XmlErrorLevel duplicateError()
		{
			return errors_.pushError("Duplicate definition",XmlErrorLevel.FATAL);
		}


		/// Get the Notation name
		private void parseDtdNotation()
		{
			int spacect = munchSpace();
			XmlString notid;
			if (!getXmlName(notid))
			{
				errors_.pushError("Notation must have a name",XmlErrorLevel.FATAL);
				return;
			}
			bool hasIllegalColon =  (namespaceAware_ && (indexOf(notid,':') >= 0));

			if (hasIllegalColon)
				errors_.pushError(format("Notation name %s with ':' while using namespace xml",notid),XmlErrorLevel.FATAL);

			if (spacect == 0)
				throw errors_.makeException(XmlErrorCode.MISSING_SPACE);

			if (validate_)
			{
				auto pnode = notid in dtd_.notationMap;
				if (pnode !is null)
				{
					//  already have error?, so ignore
				}
			}
			if (hasIllegalColon) //
				return;

			spacect = munchSpace();
			ExternalID extsrc;

			if (getExternalUri(extsrc))
			{
				if (spacect == 0)
					throw errors_.makeException(XmlErrorCode.MISSING_SPACE);
				auto xnote = new EntityData(notid,EntityType.Notation);
				xnote.src_ = extsrc;
				dtd_.notationMap[notid] = xnote;
				if (eventMode_)
					events_.notation(xnote);
			}
			else
			{
				errors_.pushError(format("NOTATION %s needs PUBLIC or SYSTEM id",notid),XmlErrorLevel.FATAL);
				return;
			}
			munchSpace();
			if (empty || front != '>')
			{
				errors_.pushError(getXmlErrorMsg(XmlErrorCode.MISSING_END_BRACKET),XmlErrorLevel.FATAL);
				return;
			}
			markupDepth--;
			docDeclare--;
			popFront();

		}
		XmlErrorLevel parseDtdElement()
		{

			munchSpace();
			XmlString ename;

			if (!getXmlName(ename))
				throw errors_.makeException(XmlErrorCode.EXPECTED_NAME);

			if (!munchSpace())
			{
				errors_.pushError(getXmlErrorMsg(XmlErrorCode.MISSING_SPACE),XmlErrorLevel.FATAL);
				throw errors_.makeException(badCharMsg(front));
			}
			ElementDef def = dtd_.elementDefMap.get(ename,null);

			if (def is null)
			{
				def = new ElementDef(ename);
				dtd_.elementDefMap[ename]=def;
			}
			else
			{
				if (validate_)
					errors_.pushError(text("Element already declared: " ,ename),XmlErrorLevel.INVALID);
			}
			def.isInternal = dtd_.isInternal_;

			// see if attributes defined for element already

			AttributeList attList = dtd_.attributeListMap.get(ename,null);

			if (attList !is null)
				def.attrList = attList;

			int listct = 0;
			while (!empty)
			{
				munchSpace();
				if (matchParen!('(')())
				{
					if (listct > 0)
						return duplicateError();
					if (def.childList is null)
						def.childList = new ChildElemList();
					collectElementList(def, def.childList, true);
					errors_.checkErrorStatus();
					listct++;

					continue;
				}
				else if (front=='>')
				{
					markupDepth--;
					docDeclare--;

					popFront();

					if (listct==0)
					{
						throw errors_.makeException("sudden end to list");
					}

					break;
				}
				if (matchInput("EMPTY"))
				{
					// mark empty
					if (listct > 0)
					{
						return duplicateError();
					}
					def.hasElements = false;
					def.hasPCData = false;
					def.hasAny = false;
					listct++;
				}
				else if (matchInput("ANY"))
				{
					if (listct > 0)
					{
						return duplicateError();
					}
					def.hasElements = true;
					def.hasPCData = true;
					def.hasAny = true;
					listct++;
				}
				else if (!empty && front == '%')
				{
					popFront();
					pushEntityContext();
				}
				else
				{
					if (front == ')')
						throw errors_.makeException("Close parenthesis mismatch");
					errors_.pushError(badCharMsg(front),XmlErrorLevel.FATAL);
					popFront();
				}
			}
			return XmlErrorLevel.OK;
		}

		bool getPublicLiteral(ref XmlString opt)
		{

			if (!empty && (front == '\"' || front == '\''))
			{
				unquoteValue(opt);
				if (opt.length == 0)
				{
					opt = "";
					return true;
				}
			}
			else
				throw errors_.makeException("Quoted PUBLIC id expected");

			int  ct = 0;
			bufAttr_.shrinkTo(0);
			auto hasSpace = false;
			foreach(dchar c; opt)
			{
				switch(c)
				{
					case 0x20:
					case 0x0A:
					case 0x0D: //0xD already filtered ?
						hasSpace = true;
						break;
					default:
						if (!isPublicChar(c))
							throw errors_.makeException(format("Bad character %x in PUBLIC Id %s", c, opt));
						if (hasSpace)
						{
							if (ct > 0)
								bufAttr_ ~= ' ';
							hasSpace = false;
						}
						ct++;
						bufAttr_ ~= c;
						break;
				}
			}
			opt = bufAttr_.data.idup;
			return true;
		}
		// Get ASCII uppercase key word.
		final bool getUpperKeyWord(ref XmlString ukw)
		{
			XmlBuffer kw;
			while(true)
			{
				if (empty)
					throw makeEmpty();
				dchar test = front;
				if (std.ascii.isUpper(test))
				{
					kw ~= test;
					popFront();
				}
				else {
					// got to be whitespace or a separator. Alpha numeric is likely wrong.
					ukw = kw.data.idup;
					if (std.ascii.isAlphaNum(test) || (ukw.length == 0))
						throw errors_.makeException(format("Upper case keyword expected: %s + %s", ukw, test));
					return ukw.length > 0;
				}
			}
		}

		final bool isOpenSquare()
		{
			if (!empty && front=='[')
			{
				squareDepth++;
				popFront();
				return true;
			}
			return false;
		}

		void doDocType()
		{
			XmlString	xmlName;
			bool hadDeclaration = hasDeclaration;
			inDTD_ = true;
			hasDeclaration = true;

			int spacect = munchSpace();

			if (! getXmlName(xmlName) )
				throw errors_.makeException("DOCTYPE name expected");
			if (!spacect)
				throw errors_.makeException("Need space before DOCTYPE name");
			munchSpace();
			if (empty)
				throw makeEmpty();
			dtd_ = new DocTypeData();
			dtd_.id_ = xmlName;
			for(;;)
			{
				munchSpace();
				if (matchInput('>'))
					break;
				if (getExternalUri(dtd_.src_))
				{
					if (!hadDeclaration)
						isStandalone_ = false;
					else
					{
						// TODO: check valid declaration?
					}
					munchSpace();

				}
				else if (isOpenSquare())
				{
					dtd_.isInternal_ = true;
					if (eventMode_)
						events_.startDoctype(this);
					docTypeInnards(DocEndType.singleDocEnd);
					if (eventMode_)
						events_.endDoctype(this);
				}
				else
				{
					throw errors_.makeException("Unknown DTD data");
				}
			}

			if (dtd_.src_.systemId_ !is null)
			{
				parseExternalDTD(dtd_.src_);
			}

			verifyGEntity();

			inDTD_ = false;


		}
		/// adjust for getting a <!
		private final bool isOpenBang()
		{
			if (!empty && front == '<')
			{
				markupDepth++;
				popFront();
				if (!empty && front == '!')
				{
					popFront();
					return true;
				}
				markupDepth--;
				unpop('<');
			}
			return false;
		}
		private final bool isCloseSquare()
		{
			if (!empty && front==']')
			{
				popFront();
				squareDepth--;
				return true;
			}
			return false;
		}
		/// adjust counts for ]]>
		private final bool isSquaredEnd()
		{
			if (!empty && front == ']')
			{
				squareDepth--;
				popFront();
				if (!empty && front == ']')
				{
					squareDepth--;
					popFront();
					if (!empty && front == '>')
					{
						markupDepth--;
						popFront();
						return true;
					}
					if (!empty)
					{
						squareDepth += 2;
						unpop("]]");
						return false;
					}
					throw errors_.makeException("Expected ']]>'");
				}
				else
				{
					squareDepth++;
					unpop(']');
					return false;
				}
			}
			return false;
		}
		private final  bool isPIStart()
		{
			if (!empty && (front == '<'))
			{
				markupDepth++;
				popFront();
				if (!empty && (front == '?'))
				{
					popFront();
					return true;
				}
				markupDepth--;
				unpop('<');
			}
			return false;
		}

		private void docTypeInnards(DocEndType endMatch)
		{
			XmlString keyword;

			while(!empty)
			{
				// before checking anything, see if character reference need decoding
				if (front == '&')
				{
					uint radix = void;
					front = expectedCharRef(radix);
				}
				munchSpace();
				final switch(endMatch)
				{
					case DocEndType.noDocEnd:
						if (empty)
							return;
						break;
					case DocEndType.singleDocEnd:
						if (isCloseSquare())
							return;
						break;
					case DocEndType.doubleDocEnd:
						if (isSquaredEnd())
							return;
						break;
				}
				if (isOpenBang())
				{
					// A DocDeclaration of some kind
					docDeclare++;

					itemCount++;
					if (isOpenSquare())
					{
						parseDtdInclude();
						continue;
					}
					if (empty)
						throw makeEmpty();
					if (matchInput("--"))
					{
						parseComment(); // TODO: stick comment somewhere ?, child of DocumentType? event?'
					}
					else {
						// A key word expected
						if (!getUpperKeyWord(keyword))
							throw errors_.makeException(format("Uppercase key word expected, not %s", keyword));
						switch(keyword)
						{
						case "ENTITY":
							parseEntity();
							break;
						case "ELEMENT":
							parseDtdElement();
							break;
						case "ATTLIST":
							parseAttList();
							break;
						case "NOTATION":
							parseDtdNotation();
							break;
						default:
							throw errors_.makeException(format("DTD unhandled keyword %s ",keyword));
						}
					}
					errors_.checkErrorStatus();
					continue;
				} // not a <! thing
				else if (matchInput('%'))
				{
					if (!pushEntityContext(false))
						if (!dtd_.isInternal_)
							throw errors_.makeException("Undefined parameter entity in external entity");
				}
				else if (isPIStart())
				{
					doProcessingInstruction();
					itemCount++;
				}
				else if (empty)
				{
					break;
				}
				else
				{
					// no valid match
					if ((endMatch == DocEndType.doubleDocEnd) && matchInput(']'))
						throw errors_.makeException("Expected ]]>");
					throw errors_.makeException(text("DTD unknown declaration: ", getSourceContext()));
				}
			}
			checkBalanced();
		}
		// check for a ; after the name
		protected final void expectEntityName(ref XmlString ename)
		{
			if (!getXmlName(ename))
				throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
			if (empty || front != ';')
				throw errors_.makeException(XmlErrorCode.BAD_ENTITY_REFERENCE);
			popFront(); // pop ;
		}
		//  got a %, so parse the name and fetch the EntityData.
		//  Uses recursive buffer, and name set to detect circular references.
		//  Entity must exist, or exception thrown.
		EntityData parseParameterEntity(bool isValue, bool allowed = true)
		{
			XmlString pname;
			expectEntityName(pname);
			if (!allowed)
			{
				// get the entity name and say its not allowed here
				throw errors_.makeException(format("parameter entity not allowed in internal subset: %s",pname));
			}
			StringSet eset;
			
			EntityData ed = getParameterEntity(pname, eset, isValue);

			if (ed is null)
			{
				throw errors_.makeException(format("Unabled to fetch entity %s",pname),XmlErrorLevel.ERROR);
			}
			return ed;
		}
		/// encounter entity reference, so start a new context
		bool pushEntityContext(bool isValue = true, char sep = 0x00, bool isallowed = true)
		{
			EntityData ed = parseParameterEntity(isValue, isallowed);
			auto content = ed.value_;
			if (content.length > 0)
			{
				if (sep)
					pushBack(sep);
				pushContext(content,false,ed);
				if (sep)
					pushBack(sep);
			}
			return true;
		}

		private bool peCheck(char sep = 0x00, bool allowed = true)
		{
			if (empty)
				return false;
			if (front != '%')
				return true;
			popFront();
			pushEntityContext(true, sep, allowed);
			return true;
		}
		/// process the ENTITY declaration
		void parseEntity()
		{
			int spacect1 = munchSpace(); // after keyword
			dchar test;

			bool isPE = matchInput('%');
			int spacect2 = munchSpace();

			if ((spacect1==0) || (isPE && (spacect2==0)))
				throw errors_.makeException("missing space in Entity definition");

			EntityData contextEntity = (isPE ? entityContext() : null);
			XmlString ename;
			if (!getXmlName(ename))
			{
				throw errors_.makeException("Entity must have a name");
			}
			spacect2 = munchSpace();
			if (namespaceAware_ && (ename.indexOf(':') >= 0))
			{
				errors_.makeException(format("Entity Name %s must not contain a ':' with namespace aware parse ", ename));
			}

			/*string sys_ref;
			string public_ref;
			string ndata_ref;*/

			EntityData edef = dtd_.getEntity( ename, isPE);

			if (isStandalone_ && isPE)
				dtd_.undeclaredInvalid_ = true;

			EntityType etype = isPE ? EntityType.Parameter : EntityType.General;
			if (edef is null)
			{
				edef = new EntityData(ename, etype);
				edef.isInternal_ = dtd_.isInternal_;
				edef.context_ = contextEntity;

				if (isPE)
					dtd_.paramEntityMap[ename] = edef;
				else
					dtd_.generalEntityMap[ename] = edef;
			}
			else
			{
				// Done this one before. Parse, but do not overwrite the first encountered version.
				edef = new EntityData(ename, etype);
				// created, check, but afterwards forget it.
				// TODO: report with warning ?
			}

			ExternalID extID;

			if (getExternalUri(extID))
			{
				if (extID.systemId_ is null)
					throw errors_.makeException("Entity ExternalID PUBLIC needs SystemLiteral");
				edef.src_ = extID;
				spacect1 = munchSpace();
				XmlString ndata_name;

				if (parseNDataName(ndata_name))
				{
					if (ndata_name.length > 0)
					{
						if (spacect1 == 0)
							throw errors_.makeException("Space needed before NDATA");
						if (isPE)
							throw errors_.makeException("NDATA cannot be in Parameter entity");
						edef.ndataref_ = ndata_name;
						/*
						auto note = dtd_.notationMap.get(ndata_name,null);
						if (note is null)//not-wf-sa-083
							throw errors_.makeException(format("No notation named %s", ndata_name));
						
						*/
					}
				}
			}
			else
			{
				XmlString estr;

				if (spacect2 == 0)
				{
					throw errors_.makeException("space needed before value");
				}
				unquoteValue(estr);
				if (estr.length > 0)
				{
					if (startsWith!("a==b")(estr,"<?xml"))
					{
						throw errors_.makeException("internal entity cannot start with declaration");
					}
					verifyParameterEntity(estr, isPE);
					edef.value_ = estr;
					edef.status_ = EntityData.Found;
					edef.reftype_ = RefTagType.ENTITY_REF;
				}
				else
				{
					edef.value_ = null;
				}
				if (edef.value_.length == 0)
				{
					edef.status_ = EntityData.Expanded;
				}
			}

			munchSpace();
			if (empty || front != '>')
			{
				throw errors_.makeException(XmlErrorCode.MISSING_END_BRACKET);
			}
			markupDepth--;
			docDeclare--;
			popFront();
		}
	}
	void bombWF_Internal(XmlString val)
	{
		throw errors_.makeException(format("Parameter Entity in %s declared value of internal subset DTD", val));
	}

	void bombWF(XmlString s)
	{
		throw errors_.makeException(format("Invalid entity reference syntax %s",s));
	}
	// syntax of parameter entity must follow the rules
	void verifyParameterEntity(XmlString s, bool isPE)
    {
        /* save previous context entity values */

        bool srcExternalEntity = this.inParamEntity();
        if (srcExternalEntity)
            srcExternalEntity = !entityContext().isInternal_;

        this.pushContext(s);
		scope(exit)
			this.popContext();

        while (!empty)
        {
            if (front == '%')
            {
                // must be part of entity definition
                popFront();
				XmlString ename;
                expectEntityName(ename);
                // can get the entity referred to?
                if (dtd_.isInternal_)
                {
                    // but if we are processing a parameter entity that is external, the rule is relaxed
                    if (!srcExternalEntity)
                    {
                        if (!isPE)
                            bombWF_Internal("General entity");
                        else
                            bombWF_Internal("Parameter entity");
                    }
                }
                else
                {
                    EntityData eref = dtd_.paramEntityMap[ename];
                    if (eref is null)
                    {
                        bombWF(s);
                    }
                }
            }
            else if (front == '&')
            {
                popFront();
                if (empty)
                    bombWF(s);

                if (front == '#')
                {
                    uint radix = void;
                    expectedCharRef(radix);
                }
                else
                {
                    if (!getXmlName(bufTag_) || empty || front != ';')
                        bombWF(s);
                    popFront();
                }
            }
            else
                popFront();
        }
    }

    bool parseNDataName(ref XmlString opt)
    {
        //ParseInput src = ctx_.in_;

        munchSpace();
        if (matchInput("NDATA"))
        {
            // reference to a notation which must be
            // declared (? in advance)
            int spacect = munchSpace();
            if (!getXmlName(bufTag_))
            {
                throw errors_.makeException("No NDATA name");
            }
            if (spacect == 0)
            {
                throw errors_.makeException("need space before NDATA name");
            }
            opt = bufTag_.data.idup;
            return true;
        }
        return false; // no such thing
    }
    /// another error type
    private final XmlErrorLevel inconsistent_separator(dchar val)
    {
        return errors_.pushError(format("inconsistent separator %x" ,val),XmlErrorLevel.INVALID);
    }
    ///  Accumulate Error report
    private final XmlErrorLevel getNoSpaceError()
    {
        return errors_.pushError(("needs a space"),XmlErrorLevel.FATAL);
    }
	/// List of child elements for ELEMENT declaration. Recursive call, so need ChildElemList argument.

	private final XmlErrorLevel fatalError(string s)
	{
		return errors_.pushError(s,XmlErrorLevel.FATAL);
	}

	private final XmlErrorLevel errorExpectSeparator()
	{
		return fatalError("Expected separator in list");
	}

	private final uint matchSeparator(ChildElemList plist, ref ChildSelect sep)
	{
		if (empty)
			return 0;

		switch(front)
		{
			case '|':
				if (sep != ChildSelect.sl_choice)
				{
					if (sep == ChildSelect.sl_one)
					{
						sep = ChildSelect.sl_choice;
						plist.select = sep;
					}
					else
						return inconsistent_separator(sep);
				}
				break;
			case ',':
				if (sep != ChildSelect.sl_sequence)
				{
					if (sep == ChildSelect.sl_one)
					{
						sep = ChildSelect.sl_sequence;
						plist.select = sep;
					}
					else
						return inconsistent_separator(sep);
				}
				break;
			default:
				// not a separator
				return false;

		}
		popFront();
		return true;
	}

    XmlErrorLevel collectElementList(ElementDef def, ChildElemList plist, bool terminator = true)
    {
        ChildSelect sep = ChildSelect.sl_one;
		XmlString keyword;

        int namect = 0;
        int defct = 0;
        bool mixedHere = false;
        bool expectSeparator = false;
        bool expectListItem = false; // true if after separator

        bool endless = true;
        while(endless)
        {
            munchSpace();
            if (matchParen!(')')())
            {
                if (defct == 0)
                {
                    return fatalError("empty definition list");
                }
                if (expectListItem)
                {
                    return fatalError("expect item after separator");
                }
                getOccurenceCharacter(plist.occurs);
                if (mixedHere)
                {
                    if (def.hasElements)
                    {
                        if (plist.occurs != ChildOccurs.oc_zeroMany)
                        {
                            return fatalError("mixed content can only be zero or more");
                        }
                    }
                    else
                    {
                        if ((plist.occurs != ChildOccurs.oc_one) && (plist.occurs != ChildOccurs.oc_zeroMany) )
                        {
                            return fatalError("pure Parsed Character data has bad occurs modifier");
                        }
                    }
                }
                break;
            }
            else if (expectSeparator && matchSeparator(plist,sep))
            {
                expectSeparator = false;
                expectListItem = true;
                continue;
            }
            if (matchParen!('(')())
            {
                if (expectSeparator)
                {
                    return errorExpectSeparator();
                }
                if (def.hasPCData)
                {
                    return fatalError("Content particles defined in mixed content");
                }
                expectListItem = false;
                ChildElemList nlist = new ChildElemList();
                plist.addChildList(nlist);
				auto errorLevel = collectElementList(def,nlist,true);
                if ( errorLevel > XmlErrorLevel.INVALID)
                    return errorLevel;
                defct += plist.length;
                expectSeparator = true;
                continue;
            }

            if (empty)
            {
                if (terminator)
                    throw makeEmpty();
                return XmlErrorLevel.OK;
            }

            switch(front)
            {
				case '#':
					popFront();
					if (expectSeparator)
						return errorExpectSeparator();

					if (!getUpperKeyWord(keyword))
						throw errors_.makeException("Keyword expected");

					if (keyword == "PCDATA")
					{
						def.hasPCData = true;
						mixedHere = true;
						if ((namect > 0) || (plist.parent !is null))
						{
							return fatalError("#PCDATA needs to be first item");
						}
					}
					else
					{
						return fatalError(format("unknown #",keyword));
					}
					defct++;
					expectSeparator = true;
					expectListItem = false;
					break;
				case '%':
					popFront();
					if (!pushEntityContext())
						return XmlErrorLevel.ERROR;
					if (dtd_.isInternal_)
					{
						popContext();
						return fatalError("Parsed entity used in internal subset definition");
					}
					break;
				default:
					//expect a name
					if (expectSeparator)
					{
						return errorExpectSeparator();
					}

					if (!getXmlName(keyword))
					{
						return fatalError("element name expected");
					}
					/*if (checkName == "CDATA")
					{
                	// test case not-wf-sa-128. Why cannot CDATA be element name?
                	return push_error("invalid CDATA");
					}
					* */
					expectListItem = false;

					ChildId child = new ChildId(keyword);
					getOccurenceCharacter(child.occurs);
					if (def.hasPCData && (child.occurs!=ChildOccurs.oc_one))
					{
						return fatalError("Content particle not allowed with PCData");
					}
					if ((plist.firstIndexOf(keyword) >= 0) && (sep == ChildSelect.sl_choice))
					{

						if (mixedHere)
						{
							if (validate_)
								errors_.pushError("Mixed content and repeated choice element",XmlErrorLevel.INVALID);
						}
						else
							return errors_.pushError("Duplicate child element name in | list",XmlErrorLevel.ERROR); //E34
					}
					else
						plist.append(child);
					defct++;
					if (namect==0)
					{
						def.hasElements = true;
					}
					namect++;
					expectSeparator = true;
            }
        }
        return XmlErrorLevel.OK;
    }
    bool getOccurenceCharacter(ref ChildOccurs occurs)
    {
        // check for + or *.

        if (empty)
            return false;

        switch(front)
        {
			case '*':
				occurs = ChildOccurs.oc_zeroMany;
				break;
			case '+':
				occurs = ChildOccurs.oc_oneMany;
				break;
			case '?':
				occurs = ChildOccurs.oc_zeroOne;
				break;
			default:
				occurs = ChildOccurs.oc_one;
				return true; // no pop
        }
        popFront();
        return true;
    }
    /// Fetch and digest these entities
    private void verifyGEntity()
    {
        //if (dtd_.GEntityMap.length > 0)
        XmlString testGEValue;
        StringSet eset;
        foreach(ge ; dtd_.generalEntityMap)
        {
            int eStatus = ge.status_;
			// not-wf-ext-sa-001
            if (eStatus > EntityData.Unknown && eStatus < EntityData.Expanded)
            {
                if (!this.isStandalone_ || ge.isInternal_)
                {
                    int reftype = RefTagType.UNKNOWN_REF;
                    eset.clear();
                    if (!lookupReference(ge.name_, eset, testGEValue, reftype))
                    {
                        throw errors_.makeException(text("Error in entity lookup: ", ge.name_));
                    }
                }
            }
            else if (ge.ndataref_.length > 0)
            {
                if (ge.isInternal_)
                {
                    int reftype =  RefTagType.UNKNOWN_REF;
                    eset.clear();
                    if (eStatus > EntityData.Unknown && eStatus < EntityData.Expanded )
                    {
                        if (!deriveEntityContent(ge, eset, reftype))
                            throw errors_.makeException(text("Error in entity ",ge.name_));
                    }
                }
            }
        }
    }


    bool lookupReference(XmlString entityName, StringSet stk, out XmlString value, out int reftype)
    {
        //DocumentType doct = docTypeNode_;
        //NamedNodeMap map = doct.getEntities();
        //Node n = map.getNamedItem(entityName);
		/*
        if (n !is null)
        {
		Entity xe = cast(Entity) n;
		reftype = (xe.getSystemId() is null) ?  RefTagType.ENTITY_REF :  RefTagType.SYSTEM_REF;
		value =  xe.getNodeValue();
		return true;
        }
		*/
        EntityData entity = dtd_.getEntity(entityName);

        if (entity is null)
        {
            reftype = RefTagType.UNKNOWN_REF;
            return false;
        }
        if (entity.status_ == EntityData.Expanded)
        {
            value = entity.value_;
            reftype = entity.reftype_;
            return true;
        }

        if (! deriveEntityContent(entity, stk, reftype))
            return false;

        switch(reftype)
        {
			case RefTagType.SYSTEM_REF:
				entity.isInternal_ = false;
				break;
			case RefTagType.NOTATION_REF:
				if (inGeneralEntity())
					throw errors_.makeException(format("Referenced unparsed data in entity %s", getEntityName()),XmlErrorLevel.ERROR);

				entity.isInternal_ = false;
				entity.status_ = EntityData.Expanded;
				entity.reftype_ = cast(RefTagType) reftype;
				break;
			default:
				break;
        }

        if (entity.status_ == EntityData.Expanded)
        {
            //Entity xe = new Entity(entity);
            //map.setNamedItem(xe);
            value = entity.value_;
            return true;
        }
        else
        {
            errors_.pushError(text("Value cannot be determined for entity: ",entity.name_),XmlErrorLevel.ERROR);
            return false;
        }
    }
    private bool deriveEntityContent(EntityData entity, StringSet stk, out int reftype)
    {

        if (isStandalone())
        {
            if (!entity.isInternal_) // w3c test sun  not-wf-sa03
            {
                errors_.pushError("Standalone yes and referenced external entity",XmlErrorLevel.FATAL);
                return false;
            }

        }
        if (entity.status_ == EntityData.Expanded)
        {
            reftype = entity.reftype_;
            return true;
        }
        if (entity.status_ < EntityData.Found)
        {
            if (entity.ndataref_.length > 0) // get the notation
            {
                reftype = RefTagType.NOTATION_REF;
                //auto nmap = docTypeNode_.getNotations();
				// auto n = nmap.getNamedItem(entity.ndataref_);
				auto n = dtd_.notationMap.get(entity.ndataref_,null);

                if (n is null)
                {
                    if (validate())
                        errors_.pushError(text("Notation not declared: ", entity.ndataref_),XmlErrorLevel.INVALID);
                    entity.status_ = EntityData.Failed;
                    return true; // need to check replaced flag!
                }
                else
                {
                    // TODO: what do do with notations?
                    entity.status_ = EntityData.Expanded;
                    return true;
                }
            }
            else if (entity.src_.systemId_ !is null)
            {
                     //Document doc = new Document();
				reftype = RefTagType.SYSTEM_REF;

                if (entity.src_.systemId_.length > 0) // and not resolved?
                {
					if (!readSystemEntity(entity))
						return false;
                }
                else
                {
                    errors_.pushError("DTD SYSTEM uri missing",XmlErrorLevel.ERROR);
                    return false;
                }
            }
            else
            {
				entity.status_ = EntityData.Expanded;
				entity.value_ = null;
				return true;
            }
        }
        // for checking well formed for standalone=yes,
        // need to fail if the original entity was internal

        if (entity.status_ == EntityData.Found) // can be empty!
        {
            if (!stk.put(entity.name_))
            {
                reftype = RefTagType.ENTITY_REF;
                errors_.pushError(text("recursion in entity lookup for ", entity.name_),XmlErrorLevel.ERROR);
                return false;
            }
            XmlBuffer tempBuf;
			XmlString tempValue;

            if (entity.value_.length > 0)
            {
                {
                    this.pushContext(entity.value_);
					scope(exit)
						this.popContext();
                    if (!textReplaceCharRef(tempBuf))
                        return false;
					tempValue = tempBuf.data.idup;
                }
				if (inDTD())
				{
 					auto pcix = tempValue.indexOf('%');
					if (pcix >= 0)
					{
						tempBuf.shrinkTo(0);
						tempBuf ~= tempValue[0..pcix];
						StringSet eset;
						this.pushContext(tempValue[pcix..$]);
						scope(exit)
							this.popContext();
						expandParameterEntities(entity.isInternal_, tempBuf, eset);
						tempValue = tempBuf.data.idup;
					}
				}

                this.pushContext(tempValue);
				scope(exit)
					this.popContext();
                entityContext(entity);

                if (!expandEntityData(tempBuf, stk, reftype))
                {
                    errors_.makeException("ENTITY value has bad or circular Reference",XmlErrorLevel.FATAL);
                    return false;
                }
                if (reftype == RefTagType.SYSTEM_REF)
                    entity.isInternal_ = false;
            }

            entity.value_ = tempValue;
            entity.status_ = EntityData.Expanded;
            stk.remove(entity.name_);
            return true;
        }
		else if (entity.status_ == EntityData.Expanded)
		{
			return true;
		}
        return false;
    }
    final private bool matchParen(dchar c)()
    {
        if (!empty && (front == c))
        {
            static if (c=='(')
            {
				parenDepth++;
				popFront();
				return true;
			}
			else if (c==')')
			{
				parenDepth--;
				popFront();
				return true;
			}
		}
		return false;
    }
	protected bool textReplaceCharRef(ref XmlBuffer app)
    {
        uint radix;
        dchar rchar = 0;
		XmlString ename;

        while (!empty)
        {
            if (lineChar_ >= 0x3FFA)
            {
                radix = 20;
            }
            if (front == '&')
            {
                //startStackID_ = stackID_;
                popFront();
                if (empty)
                    throw makeEmpty();
                if (front == '#')
                {
                    popFront();
                    refToChar(rchar);
                    app ~= rchar;
                }
                else
                {
                    // process the entity name
                    app ~= '&';
                    expectEntityName(ename);
                    app ~= ename;
                    app ~= ';';
                }
            }
            else
            {
                app ~= front;
                popFront();
            }
        }
        return (app.data.length > 0);
    }

	bool expandEntityData(ref XmlBuffer app, StringSet entityNameSet, out int refType)
    {


        uint	  radix;
        bool hitReference = false;

        //ParseInput src = sctx.in_;
		app.shrinkTo(0);
		XmlString ename;

        void putCharRef(dchar cref, uint radix)
        {
			auto w = appender!(T[])();
            app ~= "&#";
            if (radix==16)
                app ~= 'x';
			auto specstr = (radix==16) ? "%x" : "%d";
			auto spec = singleSpec(specstr);

			formatValue(w,cast(uint)cref,spec);
			app ~= w.data;
            app ~= ';';
        }

        while (true)
        {
            if (empty)
                break;
            switch(front)
            {
				case '<':
					if (isPIStart())
					{
						doProcessingInstruction();
					}
					else if (matchInput("<![CDATA["))
					{
						app ~= "<![CDATA[";

						bool hitEnd = false;

						while(!empty) // this is to validate the CDATA section ends properly
						{
							if (front == '&')
							{
								popFront();
								if (empty)
									return false;
								if (front == '#')
								{
									dchar cref = expectedCharRef(radix);
									// and output it, still as character reference
									putCharRef(cref,radix);

								}
								else
								{
									app ~= '&';
									expectEntityName(ename);
									app ~= ename;
									app ~= ';';
									//return push_error("raw & in entity value");
								}
							}
							else if (isCDataEnd())
							{
								app ~= "]]>";
								hitEnd = true;
								break;
							}
							else
							{
								app ~= front;
								popFront();
							}
						}
						if (empty && !hitEnd)
						{
							errors_.pushError("CData section did not terminate",XmlErrorLevel.ERROR);
							return false;
						}
					}
					else
					{
						app ~= front;
						popFront();

					}
					break;
				case '&':
					popFront();
					if (!empty && front=='#')
					{
						dchar uc = expectedCharRef(radix);

						if (uc == '&')
						{
							putCharRef(uc,radix);
						}
						else
						{
							app ~= uc;
						}
					}
					else
					{
						expectEntityName(ename);
						auto pc = ename in charEntity;

						if (pc !is null)
						{
							app ~= '&';
							app ~= bufTag_.data;
							app ~= ';';
						}
						else
						{
							int ref2;
							XmlString evalue;
							if (entityNameSet.contains(ename))
								throw errors_.makeException(XmlErrorCode.CIRCULAR_ENTITY_REFERENCE);
							if (!lookupReference(ename, entityNameSet, evalue, ref2))
							{
								return false;
							}
							else
							{
								if (ref2 == RefTagType.NOTATION_REF)
								{
									// ignore this reference?
								}
								if (ref2 == RefTagType.SYSTEM_REF)
									refType = RefTagType.SYSTEM_REF; // forced contamination
								app ~= evalue;
								hitReference = true;
							}
						}
					}
					break;
				default:
					app ~= front;
					popFront();
					break;
            } // end switch test
        } // end of data

        if (hitReference)
        {
            this.pushContext(app.data.idup);
			scope(exit)
				this.popContext();
            return expandEntityData(app, entityNameSet, refType);
        }
        return true;
    }

    /// integrate external DTD declarations
    void parseExternalDTD(ref ExternalID edtd)
    {
        string uri = to!string(edtd.systemId_);

        if (!findSystemPath(systemPaths_, uri, uri))
		{
			errors_.pushError(format("Cannot find file %s",uri),XmlErrorLevel.ERROR);
            return; // TODO: Exception?, record error
		}

		auto ep = prepChildParser();
		auto s = new BufferedFile(uri);
		auto sf = new XmlStreamFiller(s);
		ulong	pos;

		bool getData(ref const(dchar)[] data)
		{
			return sf.fillData(data,pos);
		}
		ep.initSource(&getData);
        ep.frontFilterOn();
		ep.dtd_ = dtd_;
		ep.isStandalone_ = false;
		
		bool wasInternal = dtd_.isInternal_;
		dtd_.isInternal_ = false;
		scope(exit)
		{
			dtd_.isInternal_ = wasInternal;
		}


		events_.startDoctype(this);
		ep.docTypeInnards(DocEndType.noDocEnd);
		events_.endDoctype(this);
    }
	// get ready a parser to read ExternalDTD or System Entity
	private ThisType prepChildParser()
	{
		auto ep = new XmlParser!T();
        ep.isEntity = true;
		ep.validate_ = validate_;
		ep.parentVersion_ = this.docVersion_;
        ep.setXmlVersion(this.docVersion_); // until we know

		// set prepareThrow handler

		ep.docInterface = this.events_;
		ep.errorInterface = this.errors_;
		ep.eventReturn = this.results_;
		ep.eventMode_ = true;

        string[]	paths;

        if (inParamEntity())
        {
            paths ~= entity.baseDir_;
        }
        paths ~= systemPaths_;
        ep.systemPaths_ = paths;

		
		return ep;
	}
	// Set up a new parser, using same IXMLEvents. Use current Xml version
    bool readSystemEntity(EntityData entity)
    {
		string uri = to!string(entity.src_.systemId_);
		auto cstr = toStringz(uri);
		// first locate the file, using this parsers system paths.
		if (entity.context_ !is null)
		{
			uri = std.path.buildPath(entity.context_.baseDir_, uri);
		}
		if (!findSystemPath(systemPaths_,uri,uri))
		{
			errors_.pushError(format( "DTD System Entity %s not found",uri), XmlErrorLevel.ERROR);
			entity.status_ = EntityData.Failed;
			return false;
		}

		auto ep = prepChildParser();
		auto s = new BufferedFile(uri);
		auto sf = new XmlStreamFiller(s);
		ulong	pos;

		bool getData(ref const(dchar)[] data)
		{
			return sf.fillData(data,pos);
		}

		ep.initSource(&getData);
        if (ep.matchInput("<?xml"))
        {
            ep.markupDepth++;
            ep.doXmlDeclaration();
        }
        XmlBuffer	edata;
 		ep.frontFilterOn();
		ep.textReplaceCharRef(edata);
		if (edata.data.length > 0)
		{
			entity.value_ = edata.data.idup;
			entity.isInternal_ = false;
			entity.baseDir_ = dirName(uri);
			entity.status_ = EntityData.Found;
		}
		else {
			entity.status_ = EntityData.Expanded;
			entity.value_ = null;
		}
		return true;
    }
	enum  kNotAllowed = "%s is not allowed in internal subset";

    void parseDtdInclude()
    {
		XmlString keyword;
        munchSpace();
        if (matchInput('%'))
        {
            pushEntityContext();
            munchSpace();
        }
        if (!getUpperKeyWord(keyword))
        {
            throw errors_.makeException(XmlErrorCode.EXPECT_INCLUDE);
        }

        munchSpace();
        if (!isOpenSquare())
        {
            throw errors_.makeException("expected '['");
        }
		bool isInternalContext =  (entity is null || entity.isInternal_);

        if (keyword == "INCLUDE")
        {
            if (dtd_.isInternal_ && isInternalContext)
                throw errors_.makeException(format(kNotAllowed, keyword));
            munchSpace();
            docTypeInnards(DocEndType.doubleDocEnd);
        }
        else if (keyword == "IGNORE")
        {
            if (dtd_.isInternal_ && isInternalContext)
                throw errors_.makeException(format(kNotAllowed, keyword));
            munchSpace();
            ignoreDocType();
        }
        else
        {
			errors_.pushError(format("Unexpected %s",keyword),XmlErrorLevel.FATAL);
            throw errors_.makeException(XmlErrorCode.EXPECT_INCLUDE);
        }
    }
    /// Count for starting <![
    final bool isSquaredStart(int extra = 1)
    {
        if (!isOpenBang())
            return false;
        if (empty || front != '[')
        {
            // undo
            markupDepth--;
            unpop("<!");
            return false;
        }
        popFront();
        squareDepth += extra;
        return true;
    }
    private void ignoreDocType()
    {
        dchar[] dfkey;

        while (!empty)
        {
            switch(front)
            {
				case '<':
					if (isSquaredStart(2)) // because of ]] at end
					{
						ignoreDocType();
					}
					else
						popFront();
					break;
				case ']':
					if (isSquaredEnd())
						return;
					popFront();
					break;
				default:
					popFront();
					break;
            }
        }
        //throwNotWellFormed("imbalanced []");
    }


    final void checkBalanced()
    {
		char[]	msg;

		auto balanceMismatchMsg()
		{
			msg.length = 0;
			if (squareDepth != 0)
				msg ~= "Mismatch of [ ] ";
			if (markupDepth != 0)
				msg ~= "Mismatch of < > ";
			if (elementDepth != 0)
				msg ~= "Mismatch of element depth ";
			if (parenDepth != 0)
				msg ~= "Mismatch of ( ) ";
			return msg;
		}

        if ((squareDepth != 0) || (markupDepth != 0) || (elementDepth != 0) || (parenDepth != 0))
        {
            if (!inParamEntity)
            {
                // do not understand the difference between xmltest\invalid--005 and not-wf-not-sa-009
				if ((markupDepth > 0) || (elementDepth > 0))
					throw errors_.makeException(text("Imbalance on end context: ", balanceMismatchMsg()));
            }
            else
            {
				if (docDeclare > 0)
					throw errors_.makeException("Parameter entity with incomplete declaration");

                if (elementDepth != 0)
                {
                    throw errors_.makeException("unbalanced element in entity content");
                }
                else if ((squareDepth==0) && (parenDepth != 0))
                {
                    if (validate_)
                        errors_.pushError("parenthesis mismatch across content source",XmlErrorLevel.INVALID);
                }
                else if (validate_)
                    errors_.pushError(text("Bad content nesting in entity ",balanceMismatchMsg()),XmlErrorLevel.INVALID);

			}
        }
    }
    /// ATTLIST .  This function is far too big
    int parseAttList()
    {
        //bool validate = true; //ctx_.validate;
        //ParseInput src = ctx.in_;
		XmlString keyword;
        int spacect =  munchSpace();
        if (front == '%')
        {
            if (!peCheck(0x20,!dtd_.isInternal_))
                return false;
            spacect = munchSpace();
        }

        if (!getXmlName(keyword))
        {
            throw errors_.makeException("Element name required for ATTLIST");
        }
        if (spacect == 0)
            throw errors_.makeException("need space before element name");
        munchSpace();
        // nice to know that element exists
        AttributeList def = dtd_.attributeListMap.get(keyword,null);

        if (def is null)
        {

            def = new AttributeList(keyword);
            //def.peRef_ = this.peReference_;
            dtd_.attributeListMap[keyword] = def;
        }

        def.isInternal_ = dtd_.isInternal_;
        // TODO : maybe replace with AttributeDef.isInternal


        ElementDef edef = dtd_.elementDefMap.get(keyword,null);

        if (edef !is null)
        {
            edef.attrList = def;
        }
        int ct = 0; // count the number of names
        while (true)
        {
            // get the name of the attribute

            string attType;

            munchSpace();

            if (!peCheck(0,!dtd_.isInternal_) && (ct == 0))
            {
                throw errors_.makeException("incomplete ATTLIST");
            }

            if (!empty && front=='>')
            {
                markupDepth--;
                popFront();
                break;
            }

            if (!getXmlName(keyword))
            {
                throw errors_.makeException("Expected attribute name");
            }
            ct++;

            AttributeDef adef = new AttributeDef(keyword);

            adef.isInternal = dtd_.isInternal_;
            if (!munchSpace())
                return false;

            if (matchInput("NOTATION"))
            {
                adef.dataform = AttributeType.att_notation;
                if (!munchSpace())
                    return false;
                if (!matchParen!('(')() || !collectAttributeEnum(adef, true))
                {
                    throw errors_.makeException("format of attribute notation");
                }

                int spct = munchSpace();

                if (matchInput('#'))
                {
                    if (!getAttributeDefault(adef.require))
                        return false;
                    spct = munchSpace();
                }

                if (empty)
                    break;
                if (front == '\'' || front == '\"')
                {
                    if (!spct)
                        throw errors_.makeException("space before value");
                    if (!addDefaultValue(adef))
                        return false;
                }
            }
            // get the type of the attribute
            else if (matchParen!'('())
            {
                adef.dataform = AttributeType.att_enumeration;
                if (!collectAttributeEnum(adef, false))
                {
                    throw errors_.makeException("format of attribute enumeration");
                }
                int spaceCt = munchSpace();

                if (matchInput('#'))
                {
                    if (!spaceCt)
                        throw errors_.makeException("Space missing");

                    if (!getAttributeDefault(adef.require))
                        return false;
                    if (adef.require == AttributeDefault.df_fixed)
                    {
                        if (! munchSpace())
                            return false;
                        if (!addDefaultValue(adef))
                            return false;
                        spaceCt =  munchSpace();
                        /*if (!unquoteValue(dfkey))
                        {
						return push_error("fixed value expected");
                        }
                        adef.values ~= toUTF8(dfkey);
                        adef.defaultIndex = adef.values.length - 1;*/
                    }
                }

                if (front == '\'' || front == '\"')
                {
                    if (!spaceCt)
                        throw errors_.makeException("space before value");
                    if (!addDefaultValue(adef))
                        return false;
                }
            }
            else
            {
                // expecting a special name
                if (!getUpperKeyWord(keyword))
                {
                    throw errors_.makeException("Expected attribute type in ATTLIST");
                }
				
                AttributeType*  patte = keyword in AttributeDef.stdAttTypeList;

                if (patte is null)
                {
                    throw errors_.makeException(text("Unknown attribute type in ATTLIST ",bufTag_));
                }
                adef.dataform = *patte;

                if (adef.dataform == AttributeType.att_id)
                {
                    // only allowed on id attribute
                    if (def.idDef !is null)
                    {
                        if (validate_)
                            errors_.pushError(text("Duplicate ID in ATTLIST: ",def.idDef.id),XmlErrorLevel.INVALID);
                    }
                    else
                    {
                        def.idDef = adef;
                        if (validate_)
							dtd_.elementIDMap[def.id] = adef.id;
                    }
                }
                // followed by maybe a default indication or list of names


                if (!peCheck(0x20,!dtd_.isInternal_))
                    return false;

                if (!munchSpace())
                    return false;


                bool enddef = false;

                while (!enddef)
                {
                    if (empty)
                        throw makeEmpty();
					if (front == '>')
                    {
						markupDepth--;
						popFront();
                        throw errors_.makeException("unfinished attribute definition");
                    }
                    if (!peCheck(0x20,!dtd_.isInternal_))
                        return false;

                    munchSpace();

                    if (empty)
                        throw makeEmpty();

                    if (front == '#')
                    {
                        popFront();
                        enddef = true;
                        if (!getAttributeDefault(adef.require))
                            return false;
                        if (adef.require == AttributeDefault.df_fixed)
                        {
                            // error if this ID
                            if (!munchSpace())
                            {
                                throw errors_.makeException("space required before value");
                            }
	
                            unquoteValue(keyword);
                            adef.values ~= keyword;
                            adef.defaultIndex = cast(int) adef.values.length - 1;
                        }
                    }
                    else if ((front=='\'')||(front=='\"'))
                    {
                        if (!addDefaultValue(adef))
                            throw errors_.makeException("Parse value failed");
                        enddef = true;
                    }
                    else
                    {
                        throw errors_.makeException(text("Unknown syntax in ATTLIST ",adef.id));
                    }
                    if (validate_ && (adef.dataform == AttributeType.att_id))
                    {
                        if ( (adef.require != AttributeDefault.df_required)
							&& (adef.require != AttributeDefault.df_implied))
                            errors_.pushError(text("Default must be #REQUIRED or #IMPLIED for ",adef.id),XmlErrorLevel.INVALID);
                    }

                }
            }
            AttributeDef existing = def.attributes_.get(adef.id, null);
            if (existing is null)
            {
                def.attributes_[adef.id] = adef;
                adef.attList = def;
            }

        }
        return true;
    }
	/// No end to attribute list functions
    uint checkAttributeValueDef(XmlString value)
    {
        // check that any entity definitions are already defined
        // at this point in the DTD parse but do not process fully.
		XmlString keyword;

        this.pushContext(value);
		scope(exit)
			this.popContext();

        uint NameExpected()
        {
            return errors_.pushError(getXmlErrorMsg(XmlErrorCode.BAD_ENTITY_REFERENCE),XmlErrorLevel.FATAL);
        }

        while(!empty)
        {
            if (front == '&')
            {
                popFront();
                if (empty)
                    return NameExpected();
                if (front == '#')
                {
                    // TODO: get valid character reference, or leave it?

                }
                else
                {
                    if (!getXmlName(keyword))
                    {
                        return NameExpected();
                    }
                    auto pc = keyword in charEntity;
                    if (pc is null)
                    {
                        EntityData edef = dtd_.getEntity(keyword);
                        if (edef is null)
                        {
                            string msg = text("Entity not defined in attribute definition ", keyword);
							auto level = (!isStandalone_) ? XmlErrorLevel.ERROR : XmlErrorLevel.FATAL;
                            throw errors_.makeException(msg,level);
                        }
                        // if notation, not a parsed entity
                        if (edef.ndataref_.length > 0)
                        {
                            errors_.makeException( text("Cannot use notation entity as value: ", keyword));
                        }

                        if (edef.src_.systemId_.length > 0)
                        {
                            errors_.makeException( text("Cannot use external entity as value: ", keyword));
                        }
                    }
                }
            }
            else
                popFront();
        }
        return true;
    }
    /// add default value to attribute definition
    uint addDefaultValue(AttributeDef attDef)
    {
        //ParseInput src = ctx.in_;
		XmlString aval;
		unquoteValue(aval);
        if (aval.length > 0)
        {
            if (!checkAttributeValueDef(aval))
            {
                throw errors_.makeException("attribute value check failed");
            }

            switch(attDef.dataform)
            {
				case AttributeType.att_id:
					if (validate_)
						errors_.pushError(text("ID attribute must not have a default value: ",attDef.id),XmlErrorLevel.INVALID);
					break;
				case AttributeType.att_nmtoken:
					if (validate_)
					{
						if (!isNmToken(aval))
							errors_.pushError(text("default value should be NMTOKEN: ",attDef.id),XmlErrorLevel.INVALID);
					}
					break;
				default:
					break;
            }


            if (attDef.values.length == 0)
            {
                attDef.values ~= aval;
                attDef.defaultIndex = 0;
            }
            else
            {
                bool att_exists = false;
                foreach(ix, s ; attDef.values)
                {
                    if (s == aval)
                    {
                        attDef.defaultIndex = cast(int)ix;
                        att_exists = true;
                        break;
                    }
                }
                if (validate_ && !att_exists)
                {
                    errors_.pushError(("default value should be in list"),XmlErrorLevel.INVALID);
                }
            }
            return true;
        }
        throw errors_.makeException("default attribute empty");
        assert(0);
    }
    /// More for the ATTLIST
    private bool getAttributeDefault(ref AttributeDefault dft)
    {
		XmlString keyword;
        if (!getUpperKeyWord(keyword))
        {
            throw errors_.makeException( "need attribute #[default]");
        }
        if (keyword == "REQUIRED")
            dft = AttributeDefault.df_required;
        else if (keyword == "IMPLIED")
            dft = AttributeDefault.df_implied;
        else if (keyword == "FIXED")
            dft = AttributeDefault.df_fixed;
        else
            throw errors_.makeException( text("Unknown attribute specification ",bufTag_));
        return true;
    }

    private final bool getXmlNmToken(ref XmlBuffer cbuf)
    {
        if (empty)
            return false;
        if ( !(isNameCharFn(front) || isNameCharFifthEdition(front)) )
            return false;
        cbuf.shrinkTo(0);
        cbuf ~= front;

        frontFilterOff();
        popFront();
        while (!empty)
        {
            if (isNameCharFn(front) || isNameCharFifthEdition(front))
            {
                cbuf ~= front;
                popFront();
            }
            else
            {
				frontFilterOn();
                return true;
            }
        }
        if (empty)
            throw makeEmpty();
        return false;
    }


    /// More for the ATTLIST
    private bool collectAttributeEnum( AttributeDef adef, bool isNotation)
    {
        // call after getting a '('
        bool gotName;

        while (!empty)
        {
            munchSpace();
            gotName = isNotation ? getXmlName(bufTag_) : getXmlNmToken(bufTag_);
            if (!gotName)
            {
                throw errors_.makeException("attribute enumeration");
            }
            adef.values ~= bufTag_.data.idup;

            munchSpace();
            if (empty)
                break;
            if (matchParen!')'())
            {
                return true;
            }
            else if (front != '|')
            {
                throw errors_.makeException(" expect | in value list");
            }
            else
                popFront();
        }
        return false;
    }
}


