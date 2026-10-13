// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ayappy-mugicha

namespace Meltype.Tests;

internal static class CliTests
{
    [Test]
    public static void Version_PrintsMeltypePrefixAndExitsZero()
    {
        var previous = Console.Out;
        using var writer = new StringWriter();
        Console.SetOut(writer);
        try
        {
            var code = Program.Main(["--version"]);
            Assert.Equal(0, code, "exit code");
            var line = writer.ToString().TrimEnd('\r', '\n');
            Assert.True(line.StartsWith("Meltype ", StringComparison.Ordinal), line);
            Assert.True(line.Length > "Meltype ".Length, line);
        }
        finally
        {
            Console.SetOut(previous);
        }
    }
}
