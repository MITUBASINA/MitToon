using System.Runtime.CompilerServices;

// development tests live outside the package (not shipped) and call a few internal diagnostics
[assembly: InternalsVisibleTo("MitToonDev.Editor")]
