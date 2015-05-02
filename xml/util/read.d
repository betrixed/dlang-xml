module xml.util.read;


import std.stream, std.path, std.file;


/// Input, a list of directories, and  file path. Search ordered directories for first match exists.
bool findSystemPath(string[] pathsList, string sysid, out string uri)
{
	uri = sysid;
	//bool isAbsolutePath = (std.path.isAbsolute(uri) ? true : false);
	bool found = exists(uri);
	if (!found)
	{
		foreach(s ; pathsList)
		{
			string syspath = std.path.buildPath(s, uri);
			found = exists(syspath);
			if (found)
			{
				//isAbsolutePath = (std.path.isAbsolute(syspath) ? true : false);
				uri = syspath;
				break;
			}
		}
	}
	return (found && isFile(uri));
}

/// check the system path can be opened for reading
/// For instance, "NUL" is a valid path and isFile returns true, but it cannot be opened or read
bool isReadable(string uri)
{
	std.stream.File f = new std.stream.File();
	f.open(uri,FileMode.In);
	if (f.isOpen)
	{
		scope(exit)
			f.close();

		return (f.available() > 0);
	}
	return false;
}

string normalizedDirName(string path)
{
	auto p = buildNormalizedPath(path);
	return dirName(p);
}


