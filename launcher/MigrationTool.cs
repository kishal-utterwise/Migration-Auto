// Launcher for Migration_Tool.bat with the app icon embedded in the exe,
// so the icon shows on any machine right after clone/pull (no shortcut needed).
// Rebuild with launcher\build.bat.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class MigrationToolLauncher
{
    [STAThread]
    static void Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;   // ends with '\', same as %~dp0
        string bat  = Path.Combine(root, "Migration_Tool.bat");
        if (!File.Exists(bat))
        {
            MessageBox.Show("Migration_Tool.bat not found next to this exe:\n" + root,
                            "Migration Tool", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden " +
            "-Command \"iex ([IO.File]::ReadAllText($env:MIG_SELF))\"");
        psi.UseShellExecute  = false;
        psi.CreateNoWindow   = true;
        psi.WorkingDirectory = root;
        psi.EnvironmentVariables["MIG_ROOT"] = root;
        psi.EnvironmentVariables["MIG_SELF"] = bat;
        Process.Start(psi);
    }
}
