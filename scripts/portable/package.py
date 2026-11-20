"""Create a categorized delivery directory and ZIP without system changes.

The development repository stays buildable. Its source is nested under
04-自定义客户端/源码; official application bundles retain their internal layout.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
TOP = 'SPR_RM26'
SOURCE = PurePosixPath('04-自定义客户端/源码')
PORTABLE = ROOT / 'scripts/portable'
PROJECT = ROOT.parents[1] if ROOT.name == SOURCE.name and ROOT.parent.name == SOURCE.parent.name else ROOT
ORGANIZED = PROJECT != ROOT
WINDOWS_CLIENT = PurePosixPath('04-自定义客户端/Windows')
WINDOWS_EXE = 'RoboMasterClient2025.exe'
WINDOWS_LAUNCHER = '8-启动Windows自定义客户端.bat'
EXCLUDED = {'08-历史备份', 'logs', 'log', 'gpucache', 'crashreport', 'crashreports',
            'punishmentrec', 'recordings', '__pycache__', '.git', '.dependencies',
            'dist', 'tmp', 'temp', 'realtimelog_rmtool'}
ROOT_ENTRIES = {
    '0-解压后先看这里.txt', '1-首次安装Windows依赖.bat',
    '2-启动Windows官方端.bat', '3-关闭并还原Windows网络.bat',
    '4-诊断Windows环境.bat', '5-首次安装Linux客户端.sh',
    '6-启动Linux自定义客户端.sh', '7-停止Linux自定义客户端.sh', '项目入口说明.md',
}
INSTALLERS = ('dotnet-runtime-7.0.4-win-x64.exe', 'VC2015~2019_redist.x64.exe',
              'DJI_Driver_Installer_32bit&64bit_4.8.11.exe')
WINDOWS_ACTIONS = {
    '1-首次安装Windows依赖.bat': 'Setup', '2-启动Windows官方端.bat': 'Start',
    '3-关闭并还原Windows网络.bat': 'Restore', '4-诊断Windows环境.bat': 'Status',
    '5-只关闭官方程序.bat': 'Stop', '6-只配置比赛网络.bat': 'Network',
    '7-应急恢复DHCP.bat': 'Dhcp',
}


def allowed(file: Path, relative: Path) -> bool:
    if not file.is_file() or file.is_symlink():
        return False
    if any(part.lower() in EXCLUDED for part in relative.parts):
        return False
    if any(part.lower().startswith('realtimelog_') for part in relative.parts):
        return False
    if file.suffix.lower() in {'.log', '.dmp', '.rdb', '.pyc'}:
        return False
    if file.name in {'CLAUDE.local.md', 'network-before.json', 'dump.rdb'}:
        return False
    if file.suffix.lower() == '.pdf':
        with file.open('rb') as stream:
            if stream.read(5) != b'%PDF-':
                return False
    return True


def files_to_package() -> dict[str, Path]:
    output = subprocess.check_output(
        ['git', '-C', str(ROOT), 'ls-files', '-z', '--cached', '--others', '--exclude-standard']
    )
    selected: dict[str, Path] = {}
    for item in output.split(b'\0'):
        if not item:
            continue
        relative = Path(item.decode('utf-8'))
        file = ROOT / relative
        if relative.as_posix() == 'config.json' or relative.as_posix() in ROOT_ENTRIES:
            continue
        if allowed(file, relative):
            selected[str(SOURCE / relative.as_posix())] = file
    kit = PROJECT / '03-官方程序' if ORGANIZED else ROOT / 'RM26_工具'
    for category in ('01-引擎', '02-选手端', '03-官方工具'):
        folder = kit / category
        if not folder.is_dir():
            raise RuntimeError(f'Missing official bundle: {folder}')
        bundle = folder
        if not ORGANIZED:
            bundles = [item for item in folder.iterdir() if item.is_dir()]
            if len(bundles) != 1:
                raise RuntimeError(f'Expected one official version directory: {folder}')
            bundle = bundles[0]
        for file in folder.rglob('*'):
            if allowed(file, file.relative_to(kit)):
                # Drop only the long outer version label, retaining every internal relative path.
                selected['03-官方程序/' + category + '/' + file.relative_to(bundle).as_posix()] = file
    manuals = PROJECT / '01-文档/官方手册' if ORGANIZED else kit / '05-官方文档'
    for file in manuals.rglob('*'):
        if allowed(file, file.relative_to(manuals)):
            selected['01-文档/官方手册/' + file.relative_to(manuals).as_posix()] = file
    for installer in INSTALLERS:
        matches = list((kit / '02-选手端').rglob(installer))
        if len(matches) != 1:
            raise RuntimeError(f'Expected one official dependency installer: {installer}')
        selected['05-安装包/Windows/' + installer] = matches[0]
    for name in ('protobuf-cpp-3.21.12.tar.gz', 'SHA256SUMS', 'README.md'):
        selected['05-安装包/Linux/' + name] = PORTABLE / 'vendor' / name
    for name in ('RM26.ps1', 'RM26.Common.ps1'):
        selected['02-运行脚本/Windows/internal/' + name] = PORTABLE / 'windows' / name
    selected['02-运行脚本/Windows/internal/project.ps1'] = PORTABLE / 'project.ps1'
    for name in ('settings.json', 'installer-hashes.json'):
        selected['06-配置/Windows/' + name] = PORTABLE / 'windows' / name
    for file in (PORTABLE / 'release').glob('*.md'):
        selected['01-文档/' + file.name] = file
    selected['打开项目.txt'] = PORTABLE / 'release/打开项目.txt'
    selected['01-文档/优化与验证记录.md'] = ROOT / 'docs/development/spr-portability-review.md'
    app = PROJECT / str(WINDOWS_CLIENT)
    if (app / WINDOWS_EXE).is_file():
        for file in app.rglob('*'):
            relative = file.relative_to(app)
            if allowed(file, relative):
                selected[str(WINDOWS_CLIENT / relative.as_posix())] = file
    return selected


def write_windows_launcher(directory: Path, name: str, action: str) -> None:
    pause = 'if not "%rc%"=="0" pause\r\n' if action == 'Custom' else 'pause\r\n'
    content = ('@echo off\r\nsetlocal\r\n'
               'powershell.exe -NoProfile -ExecutionPolicy Bypass -File '
               f'"%~dp0internal\\project.ps1" -Action {action} %*\r\n'
               'set "rc=%errorlevel%"\r\n'
               'if not "%rc%"=="0" echo Operation failed. Exit code: %rc%\r\n'
               f'{pause}exit /b %rc%\r\n')
    (directory / name).write_bytes(content.encode('ascii'))


def write_generated(directory: Path) -> None:
    windows = directory / '02-运行脚本/Windows'
    linux = directory / '02-运行脚本/Linux'
    linux.mkdir(parents=True, exist_ok=True)
    for name, action in WINDOWS_ACTIONS.items():
        write_windows_launcher(windows, name, action)
    if (directory / str(WINDOWS_CLIENT) / WINDOWS_EXE).is_file():
        write_windows_launcher(windows, WINDOWS_LAUNCHER, 'Custom')
    for name, command in {
        '5-首次安装Linux客户端.sh': 'install-client.sh',
        '6-启动Linux自定义客户端.sh': 'rm26-client.sh',
        '7-停止Linux自定义客户端.sh': 'rm26-client.sh',
    }.items():
        args = ' --stop' if name.startswith('7-') else (' "${1:---background}"' if name.startswith('6-') else '')
        content = ('#!/usr/bin/env bash\nset -euo pipefail\n'
                   'PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"\n'
                   f'exec bash "$PROJECT/04-自定义客户端/源码/scripts/portable/linux/{command}"{args}\n')
        (linux / name).write_text(content, encoding='utf-8', newline='\n')
    template = json.loads((ROOT / 'config.example.json').read_text(encoding='utf-8'))
    template['network'].update(server_ip='127.0.0.1', mqtt_broker='127.0.0.1',
                               server_port=3333, mqtt_port=3333, video_port=3334, client_robot_id=3)
    config = directory / '06-配置/Linux/config.example.json'
    config.parent.mkdir(parents=True, exist_ok=True)
    config_text = json.dumps(template, ensure_ascii=False, indent=4) + '\n'
    config.write_text(config_text, encoding='utf-8')
    app = directory / str(WINDOWS_CLIENT)
    if (app / WINDOWS_EXE).is_file():
        (app / 'config.json').write_text(config_text, encoding='utf-8')


def verify_layout(directory: Path) -> None:
    categories = {'01-文档', '02-运行脚本', '03-官方程序', '04-自定义客户端', '05-安装包', '06-配置', '07-校验清单'}
    if {file.name for file in directory.iterdir() if file.is_dir()} != categories:
        raise RuntimeError('Delivery root must contain seven category directories')
    if {file.name for file in directory.iterdir() if file.is_file()} != {'打开项目.txt'}:
        raise RuntimeError('Delivery root must have just one quick-start file')
    for file in (directory / '01-文档').rglob('*'):
        if file.is_file() and file.suffix.lower() not in {'.md', '.txt', '.pdf'}:
            raise RuntimeError(f'Non-document found in docs: {file}')
    for file in (directory / '02-运行脚本').rglob('*'):
        if file.is_file() and file.suffix.lower() not in {'.ps1', '.bat', '.sh'}:
            raise RuntimeError(f'Non-script found in launchers: {file}')
    for exe in ('RoboMasterEngine.exe', 'RoboMasterClient.exe', 'RMClientDaemon.exe'):
        if len(list((directory / '03-官方程序').rglob(exe))) != 1:
            raise RuntimeError(f'Official executable missing or ambiguous: {exe}')
    for installer in INSTALLERS:
        if not (directory / '05-安装包/Windows' / installer).is_file():
            raise RuntimeError(f'Installer missing: {installer}')
    app = directory / str(WINDOWS_CLIENT)
    if app.is_dir():
        for name in (WINDOWS_EXE, 'config.json', 'Qt6Core.dll', 'platforms/qwindows.dll', 'qml/QtQuick/qmldir'):
            if not (app / name).is_file():
                raise RuntimeError(f'Windows custom client bundle missing: {name}')
        if not (directory / '02-运行脚本/Windows' / WINDOWS_LAUNCHER).is_file():
            raise RuntimeError('Windows custom client launcher missing')


def main() -> None:
    parser = argparse.ArgumentParser()
    output_folder = PROJECT / ('08-交付与归档' if ORGANIZED else 'dist')
    parser.add_argument('--output', type=Path, default=output_folder / 'SPR_RM27_完整便携项目.zip')
    parser.add_argument('--directory', type=Path, help='Also keep an extracted copy in this new directory')
    args = parser.parse_args()
    directory = args.directory.resolve() if args.directory else None
    if directory and directory.exists():
        raise RuntimeError(f'Delivery directory exists; preserve it or choose --directory: {directory}')
    staging_parent = directory.parent if directory else args.output.resolve().parent
    staging_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.staging-', dir=staging_parent) as workspace:
        work_dir = Path(workspace)
        stage = work_dir / TOP if directory else work_dir
        stage.mkdir(exist_ok=True)
        build_package(stage, args.output)
        if directory:
            if work_dir.parent.resolve() != directory.parent or directory.exists():
                raise RuntimeError('Unsafe or occupied delivery destination')
            stage.rename(directory)


def build_package(stage: Path, output: Path) -> None:
    mapping = files_to_package()
    for name, file in sorted(mapping.items()):
        destination = stage / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, destination)
        if destination.suffix == '.ps1' and not name.startswith('03-官方程序/'):
            destination.write_bytes(file.read_text(encoding='utf-8-sig').encode('utf-8-sig'))
    write_generated(stage)
    checks = stage / '07-校验清单'
    checks.mkdir()
    verify_layout(stage)
    files = sorted(file for file in stage.rglob('*') if file.is_file())
    manifest = [{'path': file.relative_to(stage).as_posix(), 'size': file.stat().st_size} for file in files]
    (checks / '打包文件清单.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    core = []
    for name, original in mapping.items():
        if original.name in {'RoboMasterEngine.exe', 'RoboMasterClient.exe', 'RMClientDaemon.exe'}:
            with original.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            with (stage / name).open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != digest:
                    raise RuntimeError(f'Copied executable differs: {name}')
            core.append(f'{digest}  {name}')
    (checks / '官方核心程序SHA256.txt').write_text('\n'.join(core) + '\n', encoding='utf-8')
    output.parent.mkdir(parents=True, exist_ok=True)
    pending = output.with_suffix('.zip.pending')
    files = sorted(file for file in stage.rglob('*') if file.is_file())
    print(json.dumps({'phase': 'categorized_directory_ready', 'files': len(files), 'staging': str(stage)}, ensure_ascii=False), flush=True)
    with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED, compresslevel=3, allowZip64=True) as z:
        for file in files:
            relative = file.relative_to(stage).as_posix()
            z.write(file, f'{TOP}/{relative}')
            if file.suffix == '.sh':
                entry = z.getinfo(f'{TOP}/{relative}')
                entry.create_system = 3
                entry.external_attr = 0o100755 << 16
    with zipfile.ZipFile(pending) as z:
        bad = z.testzip()
        if bad:
            raise RuntimeError(f'ZIP integrity verification failed: {bad}')
        for file in files:
            if file.suffix.lower() in {'.bat', '.sh', '.ps1'}:
                if z.read(f'{TOP}/{file.relative_to(stage).as_posix()}') != file.read_bytes():
                    raise RuntimeError(f'ZIP script differs: {file}')
    pending.replace(output)
    with output.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    output.with_suffix('.zip.sha256').write_text(f'{digest}  {output.name}\n', encoding='utf-8')
    print(json.dumps({'zip': str(output), 'files': len(files),
                      'size_mb': round(output.stat().st_size / 1024**2, 1),
                      'sha256': digest, 'integrity': 'PASS'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
