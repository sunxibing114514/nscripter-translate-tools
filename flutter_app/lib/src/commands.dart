/// NScripter 命令集。
///
/// 早期 nscript_tool.py 内置了一批默认命令；
/// 后续通过 commands.txt 提供了更完整的命令表，这里直接内置完整命令表。
const List<String> _rawCommands = [
  '%', 'playstop', 'flushout', '#ffffff', '#8B0000', '#cccccc', '#444444',
  '#000000', '!s10', '!s35', '!w700', '!w3000', '!w4000', '!d4000', '!d2500',
  '!d100000', 'flushout 200', '!w2000', 'rubyoff', '!w1000', '!w2000',
  'menuselectvoice', 'lookbackcolor', 'lookbackvoice', 'mp3stop', '!d5000',
  '!w5000', 'nsadir', 'lookbackbutton', 'arc', 'labellog', 'back', 'csel',
  'pretextgosub', 'setlayer', '_csp', '_texton', '_textoff', 'loopbgmstop',
  '_stop', 'split', 'isskip', 'gettag', 'ispage', 'getpage', 'getfunction',
  'getskipoff', 'exbtn_d', 'exbtn', 'skipoff', 'getcselnum', 'getcselstr',
  'getlog', 'logsp', 'selectbtnwait', 'cselgoto', 'texthide', 'lrclick',
  'textshow', 'repaint', 'savetime', 'getsavestr', 'itoa2', 'len',
  'savefileexist', 'loadgame', 'savegame2', 'isfull', 'chvol', 'gettext',
  'getlogtext', 'strsp', 'getcursor', 'fontsize', 'bgmvol', 'se', 'transbtn',
  'allsphide', 'allspresume', 'cellcheckspbtn', 'nameset', 'chapter',
  'shadedistance', 'useescspc', 'maxkaisoupage', 'mode_wave_demo',
  'automode', 'savenumber', 'automode_time', 'btnwait2', 'bgmstop',
  'saveoff', 'savename', 'getmclick', 'getbtntimer', 'bgmonce', '!w200',
  '!d3000', '!d2000', '!d1500', '!w500', '!w250', 'strsph', 'nameSpNum',
  'lsph2', 'subtitleSpNum', 'vsp2', 'var1', 'nameSpSum', 'cos', 'angle',
  'sin', 'amsp2', 'subtitleSpOpa', 'msp2', '!w', '!d', '_sd', '_bg', 'add',
  'amsp', 'asp', 'aspp', 'asps', 'autoclick', 'avi', 'bclear', 'bcursor',
  'bdef', 'bexec', 'bg', 'bgmfadein', 'bgmfadeout', 'bgm', 'bgmvol', 'blt',
  'break', 'br', 'bsp', 'btn', 'btndef', 'btnnowindowerase', 'btnwait',
  'caption', 'cell', 'cl', 'click', 'clickstr', 'cmp', 'continue', 'csp',
  'csp2', 'cspa', 'cspc', 'dec', 'defaultfont', 'defaultspeed', 'defbgmvol',
  'definereset', 'defsevol', 'defsub', 'defvoicevol', 'delay',
  'deletescreenshot', 'dim', 'div', 'dwave', 'dwavestop', 'effect',
  'effectcut', 'effectskip', 'else', 'end', 'endif', 'erasetextwindow',
  'errorsave', 'eye', 'filelog', 'for', 'game', 'getparam', 'getspsize',
  'gettimer', 'globalon', 'gosub', 'goto', 'heartbeat', 'humanz', 'if',
  'inc', 'init', 'insertmenu', 'itoa', 'jumpb', 'kidokuskip', 'killmenu',
  'ld', 'load', 'loadgosub', 'locate', 'lookback', 'lr_trap2', 'lsp',
  'lsp2', 'lsph', 'menuselectcolor', 'menusetwindow', 'mesbox', 'mod',
  'mode_ext', 'monocro', 'mousecursor', 'mov', 'mov3', 'movl', 'mp3',
  'mp3fadeout', 'mp3loop', 'msp', 'mul', 'nega', 'next', 'noteraseman',
  'notif', 'nsa', 'numalias', 'ofscpy', 'play', 'playonce', 'print',
  'prnum', 'puttext', 'quakex', 'quakey', 'quit', 'reset', 'resetmenu',
  'resettimer', 'return', 'rlookback', 'rmenu', 'rmode', 'rnd', 'rnd2',
  'roff', 'rubyon', 'save', 'savedir', 'saveon', 'sevol', 'select',
  'selectcolor', 'selectvoice', 'selgosub', 'selnum', 'setTextWindow',
  'setTextWindow2', 'setwindow', 'setwindow3', 'skip', 'spbtn', 'spfont',
  'spi', 'spstr', 'stop', 'stralias', 'sub', 'systemcall', 'tal', 'texec',
  'textbtnwait', 'textclear', 'textgosub', 'textoff', 'texton',
  'textspeed', 'textspeeddefault', 'trap', 'transmode', 'underline',
  'usewheel', 'versionstr', 'vsp', 'wait', 'waittimer', 'wave',
  'waveloop', 'wavestop', 'windoweffect', 'windowback',
];

/// 默认命令集。
const Set<String> defaultCommands = <String>{..._rawCommands};

/// 从文本内容加载命令集：每行一个命令，忽略空行与 # 注释。
/// 返回空集合时回退到 [defaultCommands]。
Set<String> parseCommandsFile(String content) {
  final commands = <String>{};
  for (final raw in content.split('\n')) {
    final cmd = raw.trim();
    if (cmd.isEmpty || cmd.startsWith('#')) continue;
    commands.add(cmd.toLowerCase());
  }
  return commands.isNotEmpty ? commands : defaultCommands;
}