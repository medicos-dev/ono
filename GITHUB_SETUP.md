# GitHub Push Setup Guide

## Current Status
- Your remote is currently set to: `orchids-sync`
- Working tree is clean (no uncommitted changes)

## Setup GitHub Remote

### Step 1: Create a GitHub Repository
1. Go to https://github.com
2. Click the "+" icon → "New repository"
3. Name it (e.g., "ono" or "uno-game")
4. **DO NOT** initialize with README, .gitignore, or license (since you already have code)
5. Click "Create repository"

### Step 2: Add GitHub Remote

**Option A: Add GitHub as a new remote (recommended)**
```bash
git remote add github https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
```

**Option B: Replace existing remote**
```bash
git remote set-url orchids-sync https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
```

### Step 3: Push to GitHub

**If you added a new remote:**
```bash
git push -u github master
```

**If you replaced the existing remote:**
```bash
git push -u orchids-sync master
```

## If You Get Authentication Errors

### For HTTPS (recommended):
1. Use a Personal Access Token instead of password
2. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
3. Generate new token with `repo` scope
4. Use token as password when prompted

### For SSH:
1. Generate SSH key: `ssh-keygen -t ed25519 -C "your_email@example.com"`
2. Add to GitHub: Settings → SSH and GPG keys → New SSH key
3. Change remote URL: `git remote set-url github git@github.com:USERNAME/REPO.git`

## Quick Commands

Check remotes:
```bash
git remote -v
```

Push to GitHub:
```bash
git push github master
```

Pull from GitHub:
```bash
git pull github master
```
