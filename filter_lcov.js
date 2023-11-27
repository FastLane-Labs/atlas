// This script is used to filter the lcov.info file generated when running `forge coverage`
// because, by default, it includes test coverage of all script (.s.sol) and test (.t.sol) files
// which are not relevant in estimating test coverage of the repo.

const fs = require('fs');
const path = require('path');

// File paths
const lcovFile = 'lcov.info'; // Original lcov file
const filteredLcovFile = 'lcov_filtered.info'; // New filtered lcov file

// Directories to exclude from the coverage report
const excludeDirs = ['test/', 'script/'];

// Read the original lcov file
fs.readFile(lcovFile, 'utf8', (err, data) => {
  if (err) {
    console.error(`Error reading ${lcovFile}:`, err);
    return;
  }

  // Split the content into records
  const records = data.split('end_of_record\n');
  let filteredRecords = [];

  records.forEach(record => {
    const isExcluded = excludeDirs.some(dir => record.includes(`SF:${dir}`));
    if (!isExcluded) {
      filteredRecords.push(record + 'end_of_record');
    }
  });

  // Write the filtered content to a new lcov file
  fs.writeFile(filteredLcovFile, filteredRecords.join('\n'), 'utf8', err => {
    if (err) {
      console.error(`Error writing ${filteredLcovFile}:`, err);
      return;
    }
    console.log(`Filtered lcov file created at ${filteredLcovFile}`);
  });
});
