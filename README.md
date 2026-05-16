# Dotfiles

This repository contains my personal dotfiles for configuring development environments across multiple machines. It's designed to provide a consistent setup while allowing for machine-specific customizations.

## How Machine-Specific Configuration Works

This dotfiles setup automatically applies machine-specific configurations without manual setup for each new machine.

When you open a new shell:
- The `.zshrc` script determines the machine's name.
- On **macOS**, it uses the "Computer Name" (which you can see in your system settings).
- On **Linux** and other Unix-like systems, it uses the short hostname (the output of `hostname -s`).
- It then looks for a file with that name in the `~/.dotfiles/zsh/machines/` directory (e.g., `~/.dotfiles/zsh/machines/my-macbook.zsh`).
- If the file exists, it's loaded. If not, no error occurs.

This allows you to have a base configuration that works everywhere, and easily add customizations for specific machines by just adding a file.

## Usage
To install these dotfiles on a new machine, run:
```bash

bash -c "$(curl -fsSL https://raw.githubusercontent.com/biswajitpain/dotfiles/main/install.sh)"

./install.sh [local] [machine <machine_name>] [package <package_name>]

```

This command will download and execute the installation script, setting up your environment automatically.

## What's Included

- Zsh configuration with Oh My Zsh
- Machine-specific and common aliases
- Utility functions
- Git configurations (different for each machine)
- Vim settings
- Tmux configuration
- OS-specific customizations (macOS/Linux)

## Directory Structure

```
~/.dotfiles/
├── zsh/
│   ├── .zshrc
│   ├── common/
│   │   ├── aliases/
│   │   │   └── general.zsh
│   │   └── functions/
│   │       └── utils.zsh
│   ├── os/
│   │   ├── macos/
│   │   │   ├── aliases/
│   │   │   │   └── macos_aliases.zsh
│   │   │   └── functions/
│   │   │       └── macos_functions.zsh
│   │   └── linux/
│   │       ├── aliases/
│   │       │   └── linux_aliases.zsh
│   │       └── functions/
│   │           └── linux_functions.zsh
│   └── machines/
│       ├── biswajitpain-mac.zsh
│       ├── office-mac1.zsh
│       ├── office-mac2.zsh
│       ├── linux-vm1.zsh
│       ├── linux-vm2.zsh
│       └── dummy-machine.zsh
├── git/
│   ├── .gitconfig.personal-macbook
│   ├── .gitconfig.office-mac1
│   ├── .gitconfig.office-mac2
│   ├── .gitconfig.linux-vm1
│   └── .gitconfig.linux-vm2
├── vim/
│   └── .vimrc
├── tmux/
│   └── .tmux.conf
├── install.sh
└── README.md
```

## Installation Details

The `install.sh` script performs the following actions:

1. Checks for required dependencies (git, curl, zsh, vim, tmux)
2. Installs Oh My Zsh if not already present
3. Clones or updates this dotfiles repository
4. Prompts for machine type selection for Git configuration
5. Creates symlinks for configuration files
6. Sets up machine-specific Git configuration

## Customization

### Zsh

- Common aliases: `~/.dotfiles/zsh/common/aliases/general.zsh`
- Common functions: `~/.dotfiles/zsh/common/functions/utils.zsh`
- OS-specific configurations:
  - macOS: `~/.dotfiles/zsh/os/macos/`
  - Linux: `~/.dotfiles/zsh/os/linux/`
- Machine-specific configurations: `~/.dotfiles/zsh/machines/<machine-name>.zsh`

### Git

Machine-specific Git configs are stored in `~/.dotfiles/git/.gitconfig.<machine-name>`

### Vim and Tmux

- Vim: `~/.dotfiles/vim/.vimrc`
- Tmux: `~/.dotfiles/tmux/.tmux.conf`

## Adding a New Machine

Adding a new machine is simple and mostly automatic:

1.  **Zsh Configuration**:
    -   On the new machine, a Zsh configuration file will be loaded automatically from `~/.dotfiles/zsh/machines/` based on the machine's name.
    -   On macOS, the "Computer Name" is used. You can find this in `System Settings > General > About`.
    -   On Linux and other OSes, the hostname (from the `hostname -s` command) is used.
    -   To add a custom configuration for a new machine, simply create a new file in `~/.dotfiles/zsh/machines/` with the corresponding name (e.g., `my-new-mac.zsh` or `my-linux-server.zsh`). You can use `dummy-machine.zsh` as a template.

2.  **Git Configuration**:
    -   The `install.sh` script will prompt you to select a Git configuration for the new machine. You can create a new machine-specific Git config in `~/.dotfiles/git/` if needed.

## Updating

To update your dotfiles:

```bash
cd ~/.dotfiles
git pull origin main
./install.sh
```

## Troubleshooting

### Common Issues

1. **Zsh not set as default shell**: Run `chsh -s $(which zsh)`
2. **Git configuration not loading**: Ensure the correct `.gitconfig.<machine-name>` file exists and was selected during installation.
3. **Machine-specific configurations not applied**: Verify the machine name by running `scutil --get ComputerName` on macOS or `hostname -s` on other systems, and ensure the corresponding file exists in `~/.dotfiles/zsh/machines/`.

For more issues, please check the [Issues](https://github.com/biswajitpain/dotfiles/issues) section of this repository.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Oh My Zsh](https://ohmyz.sh/) for the fantastic Zsh framework
- The open-source community for inspiration and shared knowledge

## Contact

If you have any questions or suggestions, feel free to reach out:

- GitHub: [@biswajitpain](https://github.com/biswajitpain)
- Email: biswajit.pain@outlook.com

---

Happy coding, and enjoy your personalized development environment!