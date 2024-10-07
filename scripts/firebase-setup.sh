#!/bin/bash
# Function to install Homebrew (macOS only)
install_homebrew() {
  echo "Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add Homebrew to PATH
  eval "$(/opt/homebrew/bin/brew shellenv)"
}

# Function to install Node.js
install_nodejs() {
  echo "Node.js not found. Installing Node.js..."
  OS=$(uname)
  if [ "$OS" == "Darwin" ]; then
    brew install node
  elif [ "$OS" == "Linux" ]; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
  else
    echo "Unsupported OS. Please install Node.js manually."
    exit 1
  fi
}

# Function to install Google Cloud SDK (gcloud CLI)
install_gcloud_cli() {
  echo "Installing Google Cloud SDK (gcloud CLI)..."
  OS=$(uname)
  if [ "$OS" == "Darwin" ]; then
    brew install --cask google-cloud-sdk
    # Initialize gcloud
    source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc" 2>/dev/null || \
    source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.bash.inc"
  elif [ "$OS" == "Linux" ]; then
    # Remove any existing installations
    sudo apt-get remove google-cloud-sdk -y 2>/dev/null
    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates gnupg
    # Add the Cloud SDK distribution URI as a package source
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
      sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    # Import the Google Cloud public key
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
      sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    # Install the Cloud SDK
    sudo apt-get update && sudo apt-get install -y google-cloud-sdk
  else
    echo "Unsupported OS. Please install the Google Cloud SDK manually."
    exit 1
  fi
}

# Function to install Firebase CLI
install_firebase_cli() {
  echo "Installing Firebase CLI..."
  npm install -g firebase-tools
}

# Function to install jq
install_jq() {
  echo "Installing jq..."
  OS=$(uname)
  if [ "$OS" == "Darwin" ]; then
    brew install jq
  elif [ "$OS" == "Linux" ]; then
    sudo apt-get update
    sudo apt-get install -y jq
  else
    echo "Unsupported OS. Please install jq manually."
    exit 1
  fi
}

# Check for Homebrew and install if necessary (macOS only)
if [ "$(uname)" == "Darwin" ]; then
  if ! [ -x "$(command -v brew)" ]; then
    install_homebrew
  fi
fi

# Check for Node.js and install if necessary
if ! [ -x "$(command -v node)" ]; then
  install_nodejs
fi

# Check if gcloud CLI is installed
if ! [ -x "$(command -v gcloud)" ]; then
  install_gcloud_cli
fi

# Prompt for gcloud login
echo "Checking gcloud authentication..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '.'; then
  echo "No active gcloud account found. Please log in."
  gcloud auth login
else
  echo "You are already logged in to gcloud as: $(gcloud config get-value account)"
fi

# Check if Firebase CLI is installed
if ! [ -x "$(command -v firebase)" ]; then
  install_firebase_cli
fi

# Check if jq is installed
if ! [ -x "$(command -v jq)" ]; then
  install_jq
fi

echo "Starting Firebase login..."
firebase login --no-localhost
if [ $? -ne 0 ]; then
  echo "Firebase login failed. Please check your credentials and try again."
  exit 1
fi

# Ask for KMP project root directory
read -p "Enter the path to your KMP project root directory: " KMP_PROJECT_ROOT

# Verify that the directory exists
if [ ! -d "$KMP_PROJECT_ROOT" ]; then
  echo "Error: The directory '$KMP_PROJECT_ROOT' does not exist."
  exit 1
fi

# Define the paths to Android and iOS app directories
ANDROID_APP_DIR="$KMP_PROJECT_ROOT/composeApp/src/androidMain"
IOS_APP_DIR="$KMP_PROJECT_ROOT/iosApp"

# Verify that the Android and iOS directories exist
if [ ! -d "$ANDROID_APP_DIR" ]; then
  echo "Error: Android app directory '$ANDROID_APP_DIR' does not exist."
  exit 1
fi

if [ ! -d "$IOS_APP_DIR" ]; then
  echo "Error: iOS app directory '$IOS_APP_DIR' does not exist."
  exit 1
fi

# Ask for Project ID
read -p "Enter your Firebase Project ID (must be unique, e.g., my-awesome-project): " PROJECT_ID

# Ask for Android app package name
read -p "Enter your app package name for Android and iOS (e.g., com.example.app): " APP_ID

# Check if the Google Cloud project already exists
echo "Checking if the Google Cloud project '$PROJECT_ID' exists..."
PROJECT_CHECK=$(gcloud projects list --filter="projectId:$PROJECT_ID" --format="value(projectId)")

if [ "$PROJECT_CHECK" == "$PROJECT_ID" ]; then
  echo "Google Cloud project '$PROJECT_ID' already exists."
else
  # Create Google Cloud project
  echo "Creating Google Cloud project..."
  gcloud projects create "$PROJECT_ID"
  if [ $? -ne 0 ]; then
    echo "Failed to create Google Cloud project. Please check the error message above."
    exit 1
  fi
fi

gcloud config set project "$PROJECT_ID"

# Add Firebase to the existing Google Cloud project
echo "Adding Firebase to the project..."
firebase projects:addfirebase "$PROJECT_ID"
if [ $? -ne 0 ]; then
  echo "Failed to add Firebase to the project. Please check the error message above."
  exit 1
fi

# Set the current project
firebase use $PROJECT_ID

# Add Android app to the Firebase project
echo "Adding Android app to the project..."
ANDROID_APP_CREATE_OUTPUT=$(firebase apps:create android $APP_ID --project $PROJECT_ID --json)
ANDROID_APP_ID=$(echo $ANDROID_APP_CREATE_OUTPUT | jq -r '.appId')

if [ -z "$ANDROID_APP_ID" ] || [ "$ANDROID_APP_ID" == "null" ]; then
  echo "Failed to create Android app. Please check the error message above."
  exit 1
fi

# Download google-services.json directly to the Android app directory
echo "Downloading google-services.json..."
firebase apps:sdkconfig android "$ANDROID_APP_ID" --project "$PROJECT_ID" |
  tail -n +2 > "$ANDROID_APP_DIR/app/google-services.json"

# Verify that the file was downloaded
if [ ! -f "$ANDROID_APP_DIR/app/google-services.json" ]; then
  echo "Failed to download google-services.json."
  exit 1
fi

# Add iOS app to the Firebase project
echo "Adding iOS app to the project..."
IOS_APP_CREATE_OUTPUT=$(firebase apps:create ios $APP_ID --project $PROJECT_ID --json)
IOS_APP_ID=$(echo $IOS_APP_CREATE_OUTPUT | jq -r '.appId')

if [ -z "$IOS_APP_ID" ] || [ "$IOS_APP_ID" == "null" ]; then
  echo "Failed to create iOS app. Please check the error message above."
  exit 1
fi

# Download GoogleService-Info.plist directly to the iOS app directory
echo "Downloading GoogleService-Info.plist..."
firebase apps:sdkconfig ios "$IOS_APP_ID" --project "$PROJECT_ID" |
  tail -n +3 > "$IOS_APP_DIR/GoogleService-Info.plist"

# Verify that the file was downloaded
if [ ! -f "$IOS_APP_DIR/GoogleService-Info.plist" ]; then
  echo "Failed to download GoogleService-Info.plist."
  exit 1
fi

echo "Firebase project setup complete."
echo "Downloaded google-services.json and GoogleService-Info.plist."
