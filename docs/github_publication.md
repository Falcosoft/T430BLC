# Publishing on GitHub

## Create the empty repository

Create a new GitHub repository named `T430BLC`. Do not initialize it with a README, license, or `.gitignore`, because those files are already included.

## Push the generated project

Extract `T430BLC-1.0.0.zip`, open a terminal in the extracted `T430BLC` directory, and run:

```sh
git init
git add .
git commit -m "Initial release of T430BLC 1.0.0"
git branch -M main
git remote add origin https://github.com/YOUR-ACCOUNT/T430BLC.git
git push -u origin main
```

Replace `YOUR-ACCOUNT` with your GitHub user name.

## Suggested repository description

> LCD brightness control utilities for Lenovo ThinkPad T430 under real MS-DOS.

Suggested topics:

```text
ms-dos thinkpad t430 assembly tasm retrocomputing intel-graphics ivy-bridge
```

## First release

After pushing, create a GitHub release tagged `v1.0.0`. Attach hardware-built copies of `BLCSET.COM` and `BLCINIT.SYS` only after confirming that they were built from the tagged source.
