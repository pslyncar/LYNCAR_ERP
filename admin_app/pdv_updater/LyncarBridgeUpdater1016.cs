using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Threading;

namespace Lyncar.Pdv.BridgeUpdater
{
    internal static class Program
    {
        private const string Version = "1.0.16";
        private const string PackageUrl = "https://updates.lyncar.com.br/pdv/windows/PDV_Lyncar_Update_1.0.16.zip";
        private const string PackageSha256 = "FB7110E4525F57FB18D8609DA2291E54314072D1546A10722AE7851E575354E7";
        private static string _logFile = "";

        private static int Main(string[] args)
        {
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var updatesDir = Path.Combine(localAppData, "LyncarPDV", "updates");
            Directory.CreateDirectory(updatesDir);
            _logFile = Path.Combine(updatesDir, "LyncarBridgeUpdater_" + Version + ".log");

            try
            {
                Log("Bridge updater iniciado.");
                var targetDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                    "PDV Lyncar"
                );
                if (!Directory.Exists(targetDir))
                    targetDir = Path.Combine(localAppData, "Lyncar", "PDV");

                Log("Target: " + targetDir);

                if (!IsElevated() && NeedsElevation(targetDir))
                {
                    Log("Elevacao necessaria. Solicitando permissao do Windows.");
                    var code = RelaunchElevatedAndWait(args);
                    Log("Processo elevado finalizado. Codigo: " + code);
                    return code;
                }

                Directory.CreateDirectory(targetDir);
                var packagePath = Path.Combine(updatesDir, "PDV_Lyncar_Update_" + Version + ".zip");
                DownloadIfNeeded(packagePath);
                VerifyPackage(packagePath);
                ApplyPackage(packagePath, targetDir);
                Log("Atualizacao aplicada com sucesso.");
                return 0;
            }
            catch (Exception ex)
            {
                Log("ERRO: " + ex);
                return 1;
            }
        }

        private static void DownloadIfNeeded(string packagePath)
        {
            if (File.Exists(packagePath))
            {
                try
                {
                    if (Sha256(packagePath).Equals(PackageSha256, StringComparison.OrdinalIgnoreCase))
                    {
                        Log("Pacote ja baixado e valido.");
                        return;
                    }
                    File.Delete(packagePath);
                }
                catch
                {
                    try { File.Delete(packagePath); } catch { }
                }
            }

            Log("Baixando pacote: " + PackageUrl);
            using (var client = new WebClient())
            {
                client.DownloadFile(PackageUrl, packagePath);
            }
        }

        private static void VerifyPackage(string packagePath)
        {
            var hash = Sha256(packagePath);
            Log("SHA256 baixado: " + hash);
            if (!hash.Equals(PackageSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("SHA256 do pacote nao confere.");
        }

        private static void ApplyPackage(string packagePath, string targetDir)
        {
            var tempRoot = Path.Combine(Path.GetTempPath(), "LyncarBridge_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempRoot);
            try
            {
                Log("Extraindo pacote.");
                ZipFile.ExtractToDirectory(packagePath, tempRoot);
                Log("Copiando arquivos.");
                CopyDirectory(tempRoot, targetDir);
            }
            finally
            {
                try { if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, true); } catch { }
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
                var target = Path.Combine(destination, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                File.Copy(file, target, true);
            }
        }

        private static bool NeedsElevation(string targetDir)
        {
            var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            var full = Path.GetFullPath(targetDir).TrimEnd('\\') + "\\";
            if (!string.IsNullOrWhiteSpace(programFiles) &&
                full.StartsWith(Path.GetFullPath(programFiles).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
                return true;
            try
            {
                Directory.CreateDirectory(targetDir);
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

        private static int RelaunchElevatedAndWait(string[] args)
        {
            var exe = Process.GetCurrentProcess().MainModule.FileName;
            var startInfo = new ProcessStartInfo
            {
                FileName = exe,
                Arguments = "--elevated",
                Verb = "runas",
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(exe)
            };
            var process = Process.Start(startInfo);
            if (process == null) return 1;
            process.WaitForExit();
            return process.ExitCode;
        }

        private static string Sha256(string path)
        {
            using (var sha = SHA256.Create())
            using (var stream = File.OpenRead(path))
            {
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
            }
        }

        private static void Log(string message)
        {
            try
            {
                File.AppendAllText(
                    _logFile,
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine
                );
            }
            catch { }
        }
    }
}
