#!/bin/bash

# kubectl bash autocomplete setup script
# This script enables bash completion for kubectl commands

echo "=== Setting up kubectl bash autocomplete ==="

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    echo "Please install kubectl first"
    exit 1
fi

echo "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null)"

# Check if bash-completion package is installed
echo "Checking bash-completion package..."
if ! dpkg -l | grep -q bash-completion; then
    echo "Installing bash-completion package..."
    sudo apt-get update
    sudo apt-get install -y bash-completion
else
    echo "bash-completion package is already installed"
fi

# Setup kubectl completion
echo "Setting up kubectl bash completion..."

# Generate kubectl completion script
echo "Generating kubectl completion script..."
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null

# Add kubectl alias and completion to user's bashrc if not already present
BASHRC_FILE="$HOME/.bashrc"
KUBECTL_ALIAS_LINE="alias k=kubectl"
KUBECTL_COMPLETE_LINE="complete -F __start_kubectl k"

echo "Adding kubectl alias and completion to ~/.bashrc..."

# Add kubectl alias if not present
if ! grep -q "alias k=kubectl" "$BASHRC_FILE" 2>/dev/null; then
    echo "" >> "$BASHRC_FILE"
    echo "# kubectl alias" >> "$BASHRC_FILE"
    echo "$KUBECTL_ALIAS_LINE" >> "$BASHRC_FILE"
    echo "Added kubectl alias (k) to ~/.bashrc"
else
    echo "kubectl alias already exists in ~/.bashrc"
fi

# Add completion for the alias if not present
if ! grep -q "complete -F __start_kubectl k" "$BASHRC_FILE" 2>/dev/null; then
    echo "$KUBECTL_COMPLETE_LINE" >> "$BASHRC_FILE"
    echo "Added kubectl completion for alias 'k' to ~/.bashrc"
else
    echo "kubectl completion for alias 'k' already exists in ~/.bashrc"
fi

# Add source for bash completion if not present
if ! grep -q "source /usr/share/bash-completion/bash_completion" "$BASHRC_FILE" 2>/dev/null; then
    echo "" >> "$BASHRC_FILE"
    echo "# Enable bash completion" >> "$BASHRC_FILE"
    echo "if [ -f /usr/share/bash-completion/bash_completion ]; then" >> "$BASHRC_FILE"
    echo "    source /usr/share/bash-completion/bash_completion" >> "$BASHRC_FILE"
    echo "fi" >> "$BASHRC_FILE"
    echo "Added bash completion source to ~/.bashrc"
else
    echo "bash completion source already exists in ~/.bashrc"
fi

# Set proper permissions
echo "Setting proper permissions..."
sudo chmod +r /etc/bash_completion.d/kubectl

# Source the completion in current session if possible
echo "Loading bash completion in current session..."
if [ -f /usr/share/bash-completion/bash_completion ]; then
    source /usr/share/bash-completion/bash_completion
fi

if [ -f /etc/bash_completion.d/kubectl ]; then
    source /etc/bash_completion.d/kubectl
    # Set up completion for alias in current session
    complete -F __start_kubectl k 2>/dev/null || true
fi

# Test if completion is working
echo ""
echo "=== Testing kubectl completion ==="
echo "Completion setup completed!"
echo ""
echo "Available features:"
echo "✓ kubectl command completion"
echo "✓ kubectl alias 'k' (shortcut for kubectl)"
echo "✓ Completion works with alias 'k'"
echo ""
echo "To activate in current session, run:"
echo "source ~/.bashrc"
echo ""
echo "Or simply open a new terminal session."
echo ""
echo "Usage examples:"
echo "  kubectl get <TAB><TAB>     # Shows available resources"
echo "  kubectl get pods <TAB>     # Shows available pods"
echo "  k get <TAB><TAB>           # Same as kubectl (using alias)"
echo "  k describe pod <TAB>       # Shows available pods to describe"
echo ""
echo "Test completion by typing: kubectl get <TAB><TAB>"

# 佛祖保佑
echo "#                       _oo0oo_"
echo "#                      o8888888o"
echo "#                      88\" . \"88"
echo "#                      (| -_- |)"
echo "#                      0\\  =  /0"
echo "#                    ___/\\\`---\'/___"
echo "#                  .' \\\\|     |// '."
echo "#                 / \\\\|||  :  |||// \\"
echo "#                / _||||| -:- |||||- \\"
echo "#               |   | \\\\\\  -  /// |   |"
echo "#               | \\_|  ''\\---/''  |_/ |"
echo "#               \\  .-\\__  '-'  ___/-. /"
echo "#             ___'. .'  /--.--\\  \`. .'___"
echo "#          .\"\" '<  \`.___\\_<|>_/___.' >' \"\"."
echo "#         | | :  \`- \\\`.;\`\\ _ /\`;.\`/ - \` : | |"
echo "#         \\  \\ \`_.   \\_ __\\ /__ _/   .-\` /  /"
echo "#     =====\`-.____\`.___ \\_____/___.-\`___.-'====="
echo "#                       \`=---='"
echo "#"
echo "#"
echo "#     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "#"
echo "#               佛祖保佑         永無 BUG"
echo "#               佛祖保佑         永不加班"