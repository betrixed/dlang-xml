module step0;
import std.stdio, std.file;
import std.path;
import std.algorithm;
import std.net.curl;
import std.conv;
import std.stdint;
import std.string;
import std.math;
import std.format;

import xml.txml;
import texi.read;
import texi.bomstring;
import texi.buffer;
import xml.xmlError;
import xml.sax;

class StationId {
    string id_;
    string name_;
    string lat_;
    string long_;
    string hsl_;
    int    setNum_;

    this(string id)
    {
        id_ = id;
    }
};

alias ReadRange!char    RData;
alias Buffer!char       WData;
//StationId[string] stationList; // AA on name index
StationId[string] idList; //AA on Id;

void appendIndex(string fileSet, int num)
{
    int bomMark = BOM.NONE;
    auto listData = readFileBom!char(fileSet,bomMark);
    auto rd = RData(listData);
    int spaceCt = 0;
    int charCt = 0;
    dchar lastChar = 0x00;
    Buffer!char buf;
    StationId   sid = null;
    while(!rd.empty)
    {
        buf.reset();
        charCt = getCharCt(rd, buf);
        if (charCt==11)
        {
            sid = new StationId(buf.data.idup);
            sid.setNum_ = num;
            auto nameField = rd.data[1..30];
            nameField = stripRight(nameField);
            sid.name_ = tr(nameField.idup," ","_");
            rd.assign(rd.data[31..$]);
            spaceCt = getSpaceCt(rd,lastChar);
            buf.reset();
            charCt = getCharCt(rd,buf);
            sid.lat_ = buf.data.idup;
            spaceCt = getSpaceCt(rd,lastChar);
            buf.reset();
            charCt = getCharCt(rd,buf);
            sid.long_ = buf.data.idup;
            spaceCt = getSpaceCt(rd,lastChar);
            buf.reset();
            charCt = getCharCt(rd,buf);
            sid.hsl_ = buf.data.idup;
            //stationList[sid.name_] = sid;
            idList[sid.id_] = sid;
        }
        stopAfterChar(rd,0x0A);
    }
    writeln("station id count = ", idList.length);
}
// download file from URL to a filePath
void download_as_text(string fileName, string baseURL, string filePath)
{
	auto textName = setExtension(fileName, "txt");
	auto url = text(baseURL,textName);
	writeln("get: ", textName);
	string saveAs = text(filePath, textName);
	download(url,saveAs);
}

void append_as_v2(StationId sid, string srcdata, ref File fout)
{

    WData buf;
    int monthCt = 0;
    dchar lastChar = 0x00;
    long  value;
    WData temp;
    FormatSpec!char spec;

    spec.spec = 'd';
    spec.width = 5;

    RData rd = RData(srcdata);
    stopAfterChar(rd,0x0A);// strip the first line
    while(!rd.empty)
    {
        buf.reset();
        buf ~= sid.id_;
        buf ~= '0';  // Id string, plus a 'duplication indicator';
        int charCt = getCharCt(rd,buf);
        if (charCt==4)
        {
            // assemble a years data as 5 character temp fields
            monthCt = 0;
            foreach(i ; 0..12)
            {
                int spaceCt = getSpaceCt(rd,lastChar);
                temp.reset();
                charCt = getCharCt(rd,temp);
                if ((charCt==1) && (temp.data=="-"))
                {
                    // blank, a -9999
                    value = -9999;
                }
                else {
                    // shift the decimal point
                    double  checkValue = to!double(temp.data)*10.0;
                    value = lround(checkValue);
                    monthCt++;
                }
                formatValue(buf.writer, value, spec);
            }
            if (monthCt > 0)
            {
                fout.writeln(buf.data);
            }
            stopAfterChar(rd,0x0A);// read endline
        }
    }

}

void main(string[] argv)
{

	int bomMark = BOM.NONE;
	uintptr_t act = argv.length;

    uintptr_t i = 0;
    uintptr_t  fileSetNum = 0;

    while (i < act)
    {
        string arg = argv[i++];
        if (arg == "--num" && i < act)
            fileSetNum = to!uintptr_t(argv[i++]);
    }

	string baseURL;
	string inputFile;
	string outputFolder;
	string linkSearch;
	string htmlA;
	string htmlHREF;

	switch(fileSetNum)
	{
		case 1:
			{
				baseURL = "http://www.antarctica.ac.uk/met/READER/surface/";
				inputFile = "stationpt.html";
				outputFolder = "antartic1/";
				linkSearch = "All.temperature";
				htmlA = "a";
				htmlHREF = "href";

			}
			break;
		case 2:
			{

			}
			break;
		case 3:
			{
				baseURL = "https://legacy.bas.ac.uk/met/READER/aws/";
				inputFile = "awspt.html";
				outputFolder = "antartic3/";
				linkSearch = "All.temperature";
				htmlA = "a";
				htmlHREF = "href";
			}
			break;
        case 4:
            {
                // combine antartic 1,2,3 into v2 format
                auto fout = File("antarctic_dat.v2","w");
                idList.clear();
                // read list files to get the id, and mark as fileset no.
                for(int k = 1; k <= 3; k++)
                {
                    string fileSet = text("antarc",k,".list");
                    appendIndex(fileSet,k);
                }

                auto idkeys = idList.keys();
                idkeys.sort!("a < b");

                foreach(id ; idkeys)
                {
                    // read the file data, append to new v2 file, in id order
                    StationId sid = idList[id];
                    string fname = sid.name_;
                    int setNum = sid.setNum_;
                    if ((setNum==1)||(setNum==3))
                        fname = fname ~ ".All.temperature";
                    auto sourcePath = text("antarctic",setNum,"/",fname,".txt");
                    if (exists(sourcePath))
                    {
                        auto srcdata = readFileBom!char(sourcePath,bomMark);
                        append_as_v2(sid, srcdata, fout);
                    }
                    else {
                        writeln("Not found: ", sourcePath);
                    }
                }
                getchar();

            }
            return;
            //break;
		default:
			writeln("Step0 arguments --num [1,2,3,4]");
			return;
	}



	string[] myLinks;

	if (!exists(inputFile))
    {
        // download it
        auto url = text(baseURL,inputFile);
        writeln("get: ", inputFile);
        download(url,inputFile);
        if (!exists(inputFile))
        {
            writeln("Download failure: " , url);
            return;
        }
    }
	auto visitor = new SaxParser();
	visitor.isHtml(true);

	string htmldata = readFileBom!char(inputFile, bomMark);

	TagSpace mainNamespace = new TagSpace();
	auto myTLink = boyerMooreFinder(linkSearch);

	auto myLinkDg = (const SaxEvent xml) {
		auto href = xml.attributes.get(htmlHREF,"");
		if (href.length > 0)
		{
			auto r = find(href,myTLink);
			if (r.length > 0)
				myLinks ~= href;
		}
	};

	mainNamespace[htmlA, SAX.TAG_START] = myLinkDg;

	visitor.namespace = mainNamespace;
	auto handler = visitor.defaults;  // SaxParser looks after this

	try {
        visitor.setupNormalize(htmldata);
        visitor.parseDocument();
	}
	catch(XmlError ex)
	{
		writeln(ex.toString());
	}
	catch(Exception ex)
	{
		writeln(ex.msg);
	}

	foreach(link ; myLinks)
	{
		download_as_text(link, baseURL, outputFolder);
	}
	//getchar();

}
