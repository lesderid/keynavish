module keynavish.errorhandling;

import keynavish;

void showError(Stringish)(Stringish message, string title = programName)
{
    import core.sys.windows.windows : MessageBox, MB_ICONERROR;
    import std.conv : to;

    MessageBox(null, message.to!wstring.ptr, title.to!wstring.ptr, MB_ICONERROR);
}

void showWarning(Stringish)(Stringish message, string title = programName)
{
    import core.sys.windows.windows : MessageBox, MB_ICONWARNING;
    import std.conv : to;

    MessageBox(null, message.to!wstring.ptr, title.to!wstring.ptr, MB_ICONWARNING);
}

void showInfo(Stringish)(Stringish message, string title = programName)
{
    import core.sys.windows.windows : MessageBox, MB_ICONINFORMATION;
    import std.conv : to;

    MessageBox(null, message.to!wstring.ptr, title.to!wstring.ptr, MB_ICONINFORMATION);
}

template exceptionHandlerWrapper(alias func)
{
    import std.traits;
    import std.exception;
    import std.conv : to;
    import core.sys.windows.windows : MessageBox, MB_ICONERROR, MB_SYSTEMMODAL;

    extern(Windows)
    ReturnType!func exceptionHandlerWrapper(Parameters!func args) nothrow @system
    {
        try
        {
            return func(args);
        }
        catch(Throwable t)
        {
            auto message = "Unhandled exception: " ~ t.message.assumeWontThrow ~ "\r\n\r\n" ~ unhandledExceptionMessage;

            MessageBox(null, message.to!wstring.ptr, programName, MB_ICONERROR | MB_SYSTEMMODAL).assumeWontThrow;

            assert(0);
        }
    }
}