# Pi, DNS, VPN & Gateway

## Description

tbd

## Technical

### Git
```bash
$ init
$ git add README.md
$ git commit -m "Initial commit"
$ git branch -M main
```

### GitHub
```bash
$ git remote add origin https://github.com/westphilm/zerberus.git
$ git push -u origin main
```

github bereinigung
---------------------
Option B: Gleicher Repo, aber “Initial Commit” als neuer Verlauf
Variante B1 (Orphan-Branch → clean history, dann force push)

Im Repo:
```bash
git checkout --orphan clean-main
git add -A
git commit -m "Initial public release"
git branch -M main
git push --force origin main
git push --force --tags
```
+++
```bash
git branch backup-before-scrub

git filter-repo --path src/system/etc/unbound/unbound.conf.d/unbound-pi-hole.conf --invert-paths

git push --force --all
git push --force --tags

git log --all -- src/system/etc/unbound/unbound.conf.d/unbound-pi-hole.conf

git fetch
git reset --hard origin/main
```
