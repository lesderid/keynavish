module keynavish.errorhandling;

@system nothrow:

void showError(string message, string title = "keynavish")
{
    import core.sys.windows.windows : MessageBox, MB_ICONERROR;
    import std.conv : to;
    import std.exception : assumeWontThrow;

    MessageBox(null, message.to!wstring.assumeWontThrow.ptr, title.to!wstring.assumeWontThrow.ptr, MB_ICONERROR);
}