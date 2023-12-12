const fs = require('fs');
const { exec } = require('child_process');

// Array of files to be ignored during coverage checks
let filesToIgnore = [
  'test/V4SwapIntent.t.sol', // Add more files here as needed
];

// Function to rename a file
function renameFile(oldName, newName) {
  return new Promise((resolve, reject) => {
    fs.rename(oldName, newName, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

// Function to execute a command
function executeCommand(command) {
  return new Promise((resolve, reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error: ${error}`);
        reject(error);
      }
      console.log(`stdout: ${stdout}`);
      console.error(`stderr: ${stderr}`);
      resolve();
    });
  });
}

// Function to rename files in the ignore list
async function renameFiles(extensionFrom, extensionTo) {
  for (let i = 0; i < filesToIgnore.length; i++) {
    const newName = filesToIgnore[i].replace(extensionFrom, extensionTo);
    await renameFile(filesToIgnore[i], newName);
    filesToIgnore[i] = newName; // Update the array with the new file name
  }
}

async function runCoverage() {
  try {
    // Rename .sol files to .txt
    await renameFiles('.sol', '.txt');

    // Run coverage command
    await executeCommand('forge coverage --ir-minimum --report lcov && node filter_lcov.js && genhtml lcov_filtered.info --output-directory report && open report/index.html');

    // Rename .txt files back to .sol
    await renameFiles('.txt', '.sol');
  } catch (error) {
    console.error('An error occurred:', error);
  }
}

runCoverage();
