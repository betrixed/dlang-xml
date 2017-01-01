module xml.sax;

import xml.txml, xml.xmlError;
import xml.dom.domt;
import xml.xmlSax;
import xml.util.bomstring;

alias xml.xmlSax.XMLSAX!char	SaxTpl;
alias SaxTpl.Sax		Sax;
alias SaxTpl.SaxDg		SaxDg;
alias SaxTpl.SaxParser  SaxParser;
alias SaxTpl.SaxEvent   SaxEvent;
alias SaxTpl.TagSpace	TagSpace;
