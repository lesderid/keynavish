module keynavish.errorhandling;

import keynavish;

@system nothrow:

void showError(Stringish)(Stringish message, string title = programName)
{
    import core.sys.windows.windows : MessageBox, MB_ICONERROR;
    import std.conv : to;
    import std.exception : assumeWontThrow;

    MessageBox(null, message.to!wstring.assumeWontThrow.ptr, title.to!wstring.assumeWontThrow.ptr, MB_ICONERROR);
}

void showWarning(Stringish)(Stringish message, string title = programName)
{
    import core.sys.windows.windows : MessageBox, MB_ICONWARNING;
    import std.conv : to;
    import std.exception : assumeWontThrow;

    MessageBox(null, message.to!wstring.assumeWontThrow.ptr, title.to!wstring.assumeWontThrow.ptr, MB_ICONWARNING);
}

void showInfo(Stringish)(Stringish message, string title = programName)
{
    import core.sys.windows.windows : MessageBox, MB_ICONINFORMATION;
    import std.conv : to;
    import std.exception : assumeWontThrow;

    MessageBox(null, message.to!wstring.assumeWontThrow.ptr, title.to!wstring.assumeWontThrow.ptr, MB_ICONINFORMATION);
}