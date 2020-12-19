module keynavish.main;

import core.sys.windows.windows;
import keynavish.keynavish;

@system nothrow:

alias extern(C) int function(string[] args) MainFunc;
extern (C) int _d_run_main(int argc, char **argv, MainFunc mainFunc);

extern (Windows)
int WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    return _d_run_main(0, null, &_main); // arguments unused, retrieved via CommandLineToArgvW
}

extern(C)
int _main(string[] args)
{
    run();

	return 0;
}