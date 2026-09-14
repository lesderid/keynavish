module keynavish.errorhandling;

import keynavish;

version (Windows)
{
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
}
else
{
    //
    // NSAlert, presented asynchronously on the main queue by the shim.
    //
    // Showing a modal alert synchronously would be a correctness bug, not just a
    // style one: several of these are reachable from inside the CGEventTap
    // callback, and blocking the run loop there gets the tap disabled by
    // timeout. See MACOS-PORT.md §6.12.
    //

    private const(char)* cstring(Stringish)(Stringish message)
    {
        import std.conv : to;
        import std.string : toStringz;

        return message.to!string.toStringz;
    }

    void showError(Stringish)(Stringish message)
    {
        import keynavish.platform.macos.shim : knv_alert_error;

        knv_alert_error(message.cstring);
    }

    void showWarning(Stringish)(Stringish message)
    {
        import keynavish.platform.macos.shim : knv_alert_warning;

        knv_alert_warning(message.cstring);
    }

    void showInfo(Stringish)(Stringish message)
    {
        import keynavish.platform.macos.shim : knv_alert_info;

        knv_alert_info(message.cstring);
    }
}

template exceptionHandlerWrapper(alias func)
{
    import std.traits;
    import std.exception;

    version (Windows)
    {
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
    else
    {
        extern(C)
        ReturnType!func exceptionHandlerWrapper(Parameters!func args) nothrow @system
        {
            try
            {
                return func(args);
            }
            catch(Throwable t)
            {
                import core.stdc.stdio : fprintf, stderr;
                import std.string : toStringz;

                auto message = ("Unhandled exception: " ~ t.message.assumeWontThrow ~ "\n\n" ~ unhandledExceptionMessage).assumeWontThrow;

                fprintf(stderr, "%s\n", message.toStringz.assumeWontThrow);
                showError(message).assumeWontThrow;

                assert(0);
            }
        }
    }
}
