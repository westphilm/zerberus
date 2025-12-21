# Deployment

## `Pi Gateway Zerberus`

### Git 
#### git clone
```bash
  $ git clone https://github.com/westphilm/zerberus.git
```

#### git pull
```bash
  /opt/zerberus $ git pull
  /opt/zerberus $ chmod +x deploy.py
```

```bash
  /opt/zerberus $ sudo ./deploy.py --dry-run
```
---

#### Errorhandling
```bash
  /opt/zerberus $ sudo ./deploy.py --dry-run
ERROR: PyYAML not available. Install with: sudo apt-get install -y python3-yaml
Traceback (most recent call last):
File "/opt/zerberus/./deploy.py", line 14, in <module>
import yaml  # type: ignore
^^^^^^^^^^^
```

```bash
  /opt/zerberus $ sudo apt-get install -y python3-yaml
```

```bash
  /opt/zerberus $ sudo ./deploy.py --dry-run
```
---

