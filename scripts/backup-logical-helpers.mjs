export function quoteCmdArg(value) {
  const text = String(value);
  if (text.length === 0) return '""';
  if (!/[ \t"]/u.test(text)) return text;
  return `"${text.replaceAll('"', '\\"')}"`;
}

export function buildWindowsCommandLine(command, args) {
  return [command, ...args].map(quoteCmdArg).join(' ');
}

export function runCrossPlatform(command, args, options = {}) {
  if (process.platform === 'win32') {
    return {
      command: process.env.ComSpec ?? 'cmd.exe',
      args: ['/d', '/s', '/c', buildWindowsCommandLine(command, args)],
      options,
    };
  }

  return {
    command,
    args,
    options,
  };
}
