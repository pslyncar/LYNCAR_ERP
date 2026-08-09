using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Security.Principal;
using System.Threading;

namespace Lyncar.Pdv.Updater
{
    internal static class Program
    {
        private static string _logFile = "";

        private static int Main(string[] args)
        {
            var parsed = ParseArgs(args);
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var logDir = Path.Combine(localAppData, "LyncarPDV", "updates");
            Directory.CreateDirectory(logDir);
            _logFile = Path.Combine(logDir, "LyncarUpdater.log");

            try
            {
                var packagePath = Required(parsed, "package");
                var targetDir = Required(parsed, "target");
                var restartExe = parsed.ContainsKey("restart") ? parsed["restart"] : "";
                var pidText = parsed.ContainsKey("pid") ? parsed["pid"] : "";

                Log("Updater iniciado.");
                Log("Package: " + packagePath);
                Log("Target: " + targetDir);

                if (!File.Exists(packagePath))
                    throw new FileNotFoundException("Pacote de atualizacao nao encontrado.", packagePath);
                if (!Directory.Exists(targetDir))
                    throw new DirectoryNotFoundException("Pasta do PDV nao encontrada: " + targetDir);

                if (!IsElevated() && NeedsElevation(targetDir))
                {
                    Log("Elevacao necessaria. Reabrindo updater como administrador.");
                    RelaunchElevated(args);
                    return 0;
                }

                int pid;
                if (int.TryParse(pidText, out pid))
                    WaitForProcessExit(pid);

                var tempRoot = Path.Combine(Path.GetTempPath(), "LyncarPDVUpdate_" + Guid.NewGuid().ToString("N"));
                Directory.CreateDirectory(tempRoot);
                try
                {
                    ExtractZip(packagePath, tempRoot);
                    CopyDirectory(tempRoot, targetDir);
                    Log("Arquivos atualizados com sucesso.");
                }
                finally
                {
                    TryDeleteDirectory(tempRoot);
                }

                if (!string.IsNullOrWhiteSpace(restartExe) && File.Exists(restartExe))
                {
                    Log("Reabrindo PDV.");
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = restartExe,
                        UseShellExecute = true,
                        WorkingDirectory = Path.GetDirectoryName(restartExe)
                    });
                }

                return 0;
            }
            catch (Exception ex)
            {
                Log("ERRO: " + ex);
                return 1;
            }
        }

        private static Dictionary<string, string> ParseArgs(string[] args)
        {
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < args.Length; i++)
            {
                var key = args[i];
                if (!key.StartsWith("--", StringComparison.Ordinal)) continue;
                key = key.Substring(2);
                var value = "true";
                if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
                    value = args[++i];
                result[key] = value;
            }
            return result;
        }

        private static string Required(Dictionary<string, string> args, string key)
        {
            if (!args.ContainsKey(key) || string.IsNullOrWhiteSpace(args[key]))
                throw new ArgumentException("Parametro obrigatorio ausente: --" + key);
            return args[key];
        }

        private static void WaitForProcessExit(int pid)
        {
            Log("Aguardando PDV encerrar. PID: " + pid);
            for (var i = 0; i < 120; i++)
            {
                try
                {
                    var process = Process.GetProcessById(pid);
                    if (process.HasExited) return;
                }
                catch
                {
                    return;
                }
                Thread.Sleep(500);
            }
        }

        private static bool NeedsElevation(string targetDir)
        {
            var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            var full = Path.GetFullPath(targetDir).TrimEnd('\\') + "\\";
            if (!string.IsNullOrWhiteSpace(programFiles) &&
                full.StartsWith(Path.GetFullPath(programFiles).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
                return true;
            if (!string.IsNullOrWhiteSpace(programFilesX86) &&
                full.StartsWith(Path.GetFullPath(programFilesX86).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
                return true;

            try
            {
                var test = Path.Combine(targetDir, ".lyncar_write_test");
                File.WriteAllText(test, "ok");
                File.Delete(test);
                return false;
            }
            catch
            {
                return true;
            }
        }

        private static bool IsElevated()
        {
            using (var identity = WindowsIdentity.GetCurrent())
            {
                var principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        private static void RelaunchElevated(string[] args)
        {
            var exe = Process.GetCurrentProcess().MainModule.FileName;
            var startInfo = new ProcessStartInfo
            {
                FileName = exe,
                Arguments = QuoteArgs(args),
                Verb = "runas",
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(exe)
            };
            Process.Start(startInfo);
        }

        private static string QuoteArgs(string[] args)
        {
            var quoted = new List<string>();
            foreach (var arg in args)
                quoted.Add("\"" + arg.Replace("\"", "\\\"") + "\"");
            return string.Join(" ", quoted);
        }

        private static void ExtractZip(string zipPath, string destination)
        {
            Log("Extraindo pacote.");
            using (var archive = ZipFile.OpenRead(zipPath))
            {
                foreach (var entry in archive.Entries)
                {
                    var targetPath = Path.GetFullPath(Path.Combine(destination, entry.FullName));
                    if (!targetPath.StartsWith(Path.GetFullPath(destination), StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("Entrada invalida no pacote: " + entry.FullName);

                    if (string.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(targetPath);
                        continue;
                    }

                    Directory.CreateDirectory(Path.GetDirectoryName(targetPath));
                    entry.ExtractToFile(targetPath, true);
                }
            }
        }

        private static void CopyDirectory(string source, string destination)
        {
            foreach (var dir in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
            {
                var relative = dir.Substring(source.Length).TrimStart('\\');
                Directory.CreateDirectory(Path.Combine(destination, relative));
            }

            foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
            {
                var relative = file.Substring(source.Length).TrimStart('\\');
                if (relative.Equals("LyncarUpdater.exe", StringComparison.OrdinalIgnoreCase))
                {
                    Log("Mantendo updater atual em uso.");
                    continue;
                }
                var target = Path.Combine(destination, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                File.Copy(file, target, true);
            }
        }

        private static void TryDeleteDirectory(string path)
        {
            try { if (Directory.Exists(path)) Directory.Delete(path, true); } catch { }
        }

        private static void Log(string message)
        {
            try
            {
                File.AppendAllText(_logFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine);
            }
            catch { }
        }
    }
}
