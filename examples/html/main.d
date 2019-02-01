module main;

import std.stdio;
import std.stdint;

import xml.sax;
import xml.parser;
import xml.error;
import std.stdio;
import std.file;
import std.string;
import xml.util.buffer;


    alias Sax!char         Sfx;
    alias Sax!char.SaxDg   SaxDg;
    alias XmlEvent!char    SaxEvent;
    alias TagSpace!char    DgSet;

int main(string[] argv)
{
    string inputFile;
    uintptr_t act = argv.length;

    uintptr_t i = 0;

    while (i < act)
    {
        string arg = argv[i++];
        if (arg == "--input" && i < act)
            inputFile = argv[i++];
    }

    auto tv = new SaxParser!char();

    if (!exists(inputFile))
        {
            auto msg = format("%s not found : in dir %s", inputFile, getcwd());
            writeln(msg);
            getchar();
            return -1;
        }
    tv.setupFile(inputFile);

    auto nspace = new DgSet();
    auto dspace = new DgSet();
    auto cspace = new DgSet();

    alias void delegate( const(char)[] s) LineDg;

    class DataRow {
        string[] data;
        this(string[] row) {
            data = row;
        }
    }

    class ForCSV {
        string[]  header;
        DataRow[] doctable;

        void setHeader(string[] hdr) {
            header = hdr;
        }
        void addRow(DataRow row) {
            doctable ~= row;
        }

        uintptr_t length() {
            return doctable.length;
        }
        static void formatLine(string[] line, LineDg dg) {
            Buffer!char buffer;

            foreach(size_t i, s ; line) {
                if (i > 0) {
                    buffer ~= ",";
                }
                buffer ~= format("\"%s\"", s );
            }
            buffer ~= "\n";
            dg(buffer.peek);
        }

        void output(LineDg dg) {
            formatLine(header, dg);
            foreach( dr ; doctable)
            {
                formatLine(dr.data, dg);
            }
        }
    }

    auto csv =  new ForCSV();

    csv.setHeader( ["#","Country", "pop-2025", "pop-2017", "GDP-2025", "GDP-2017", "Mil.Exp-2025", "Mil.Exp-2017", "PPP-2025", "PPP-2017" ] );

    string[]    row;

    SaxDg textDg = (const SaxEvent xml)
    {
        auto s = xml.data.idup;

        if (s.length > 0) {
            if (s[0] == '$')
                s = s[1..$];
            if (s.length > 0)
                row ~= s;
            else {
                row ~= "-";
            }
        }

    };


    cspace["a", SAX.TEXT] = textDg;
    cspace["span", SAX.TEXT] = textDg;
    cspace["td", SAX.TEXT] = textDg;

    SaxDg startCell = (const SaxEvent xml) {
        tv.pushNamespace(cspace);
    };
    SaxDg endCell = (const SaxEvent xml) {
        tv.popNamespace();
    };
    SaxDg endRow = (const SaxEvent xml)
    {
        if (row.length > 0) {
            csv.addRow( new DataRow(row) );
            row.length = 0;
        }
        tv.popNamespace();
    };
    dspace["tr", SAX.TAG_END] = endRow;
    dspace["td", SAX.TAG_START] = startCell;
    dspace["td", SAX.TAG_END] = endCell;

    SaxDg startRow =  (const SaxEvent xml)
    {
        tv.pushNamespace(dspace);
    };

    nspace["tr",SAX.TAG_START] = startRow;

    tv.namespace = nspace;
    try {
        tv.isHtml(true);
        tv.parseDocument();
    }
    catch (XmlError e) {
        writeln("Error: ", e.toString());
    }
    writeln("Rows = ", csv.length);

    void output(const(char)[] s) {
        write(s);
    }

    csv.output(&output);
    getchar();
    return 0;
}
