module keynavish.errorhandling;

import keynavish;

void showError(Stringish)(Stringish message)
{
    import core.sys.windows.windows : MessageBox, MB_ICONERROR;
    import std.utf : toUTF16z;

    MessageBox(null, message.toUTF16z, programName.ptr, MB_ICONERROR);
}

void showWarning(Stringish)(Stringish message)
{
    import core.sys.windows.windows : MessageBox, MB_ICONWARNING;
    import std.utf : toUTF16z;

    MessageBox(null, message.toUTF16z, programName.ptr, MB_ICONWARNING);
}

void showInfo(Stringish)(Stringish message)
{
    import core.sys.windows.windows : MessageBox, MB_ICONINFORMATION;
    import std.utf : toUTF16z;

    MessageBox(null, message.toUTF16z, programName.ptr, MB_ICONINFORMATION);
}

template exceptionHandlerWrapper(alias func)
{
    import std.traits;
    import std.exception;
    import std.utf : toUTF16z;
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

            MessageBox(null, message.toUTF16z, programName.ptr, MB_ICONERROR | MB_SYSTEMMODAL).assumeWontThrow;

            assert(0);
        }
    }
}