set -e
source .env

# Even if the first command fails the second runs. Not sure why npm doesn't give me a non zero exit code.
npm run -w downstream deploy:local:all
npm run -w contracts init:local