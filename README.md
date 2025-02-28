
```markdown
# Dotfiles

This repository contains my personal dotfiles for configuring development environments across multiple machines. It's designed to provide a consistent setup while allowing for machine-specific customizations.

## Supported Machines

- Personal MacBook
- Office Mac 1
- Office Mac 2
- Linux VM 1
- Linux VM 2



```

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
│       ├── personal-macbook.zsh
│       ├── office-mac1.zsh
│       ├── office-mac2.zsh
│       ├── linux-vm1.zsh
│       └── linux-vm2.zsh
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
4. Prompts for machine type selection
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

1. Create a new machine-specific Zsh config in `~/.dotfiles/zsh/machines/`
2. Create a new Git config in `~/.dotfiles/git/`
3. Update the `determine_machine_type()` function in `install.sh`

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
2. **Git configuration not loading**: Ensure the correct `.gitconfig.<machine-name>` file exists
3. **Machine-specific configurations not applied**: Check that the machine name in `.machine_type` matches your Zsh and Git config filenames

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
```

This README provides:

1. An overview of your dotfiles and supported machines
2. Quick start instructions
3. A detailed explanation of what's included and the directory structure
4. Installation details
5. Customization guidelines
6. Instructions for adding new machines
7. Update process
8. Troubleshooting section
9. Contribution guidelines
10. License information
11. Acknowledgments and contact information

Feel free to adjust any part of this README to better match your specific setup or preferences. You may want to add or remove sections based on the complexity of your dotfiles and the level of detail you want to provide to users.