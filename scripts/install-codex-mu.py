"""Install the scoped mu profile and command groups without replacing user config."""

import argparse
import ast
from pathlib import Path


def write_config(path: Path, content: str) -> None:
    if path.exists() and path.read_text() == content:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        backup = path.with_name(path.name + '.bak')
        while backup.exists():
            backup = backup.with_name(backup.name + '.bak')
        backup.write_text(path.read_text())
    path.write_text(content)
    print(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mu-dir', type=Path, default=Path('/opt/Projects/mu'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--consolidate-rules', action='store_true',
                        help='retire obsolete mu-specific allow rules, preserving other projects')
    args = parser.parse_args()
    mu = args.mu_dir.expanduser().resolve()
    if not (mu / 'src/mu').is_dir():
        parser.error('--mu-dir must name a mu checkout')
    config_home = Path.home() / '.codex'
    targets = {
        config_home / 'mu.config.toml': (mu / '.codex/config.toml').read_text(),
        config_home / 'rules/mu.rules': (mu / '.codex/rules/mu.rules').read_text(),
    }
    if args.dry_run:
        for path, content in targets.items():
            print(f'{path}\n{content}')
        return
    for path, content in targets.items():
        write_config(path, content)
    if args.consolidate_rules:
        default_rules = config_home / 'rules/default.rules'
        if default_rules.exists():
            kept = []
            removed = 0
            for line in default_rules.read_text().splitlines(keepends=True):
                try:
                    call = ast.parse(line).body[0].value
                    fields = {k.arg: ast.literal_eval(k.value) for k in call.keywords}
                    pattern = fields.get('pattern', [])
                    tokens = [str(mu), str(Path.home() / '.mu'), '~/.mu/', 'src/mu/']
                    mu_specific = any(token in arg for token in tokens for arg in pattern
                                      if isinstance(arg, str))
                    mu_commit = pattern[:2] == ['git', 'commit'] and any(
                        arg.startswith(('mu: ', 'mine: ')) for arg in pattern
                        if isinstance(arg, str))
                    retire = fields.get('decision', 'allow') == 'allow' and (mu_specific or mu_commit)
                except (SyntaxError, ValueError, IndexError, AttributeError):
                    retire = False
                if retire:
                    removed += 1
                else:
                    kept.append(line)
            if removed:
                write_config(default_rules, ''.join(kept))
                print(f'Retired {removed} mu-specific allow rules; other rules preserved.')



if __name__ == '__main__':
    main()
