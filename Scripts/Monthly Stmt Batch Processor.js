// Monthly Statement Generation Batch Processor

const axios = require('axios');
const { exec } = require('child_process'); // To execute shell commands

// Configuration
const API_BASE_URL = 'https://api.example.com/report'; // Replace with your API base URL
const BATCH_SIZE = 10; // Number of merchant IDs per batch
const WAIT_TIME_BETWEEN_BATCHES = 4 * 60 * 1000; // 4 minutes in milliseconds
const WAIT_TIME_AFTER_UPDATE = 0.5 * 60 * 1000; // 30 seconds in milliseconds

// Manually set start and end datetime
const startOfPreviousMonth = '2025-01-01T00:00:00.000Z'; // Update manually
const endOfPreviousMonth = '2025-01-31T00:00:00.000Z'; // Update manually

// List of merchant IDs (Populate externally)
const merchantIds = []; // Ensure this is populated from a secure source

// Helper function to get the current timestamp
function getTimestamp() {
  return new Date().toISOString();
}

// Function to calculate the estimated total time
function calculateEstimatedTime() {
  const totalMerchants = merchantIds.length;
  const numBatches = Math.ceil(totalMerchants / BATCH_SIZE);
  const totalWaitTimePerBatch = WAIT_TIME_BETWEEN_BATCHES + WAIT_TIME_AFTER_UPDATE;
  const estimatedTimeMs = numBatches * totalWaitTimePerBatch;
  const estimatedMinutes = Math.ceil(estimatedTimeMs / (60 * 1000));
  return estimatedMinutes;
}

// Simulate the process for a single batch
async function processBatch(batch) {
  try {
    console.log(`[${getTimestamp()}] Processing batch: ${batch}`);

    // Call the `merchant-statement` API
    console.log(`[${getTimestamp()}] Triggering merchant-statement...`);
    const response = await axios.post(`${API_BASE_URL}/merchant-statement`, {
      merchants: batch,
      startOfPreviousMonth,
      endOfPreviousMonth,
    });
    console.log(`[${getTimestamp()}] Merchant statement response:`, response.data);

    // Wait for batch processing to complete
    console.log(`[${getTimestamp()}] Waiting 4 minutes for snapshot jobs to complete...`);
    await new Promise((resolve) => setTimeout(resolve, WAIT_TIME_BETWEEN_BATCHES));

    // Call the `update` API
    console.log(`[${getTimestamp()}] Triggering update...`);
    const updateResponse = await axios.post(`${API_BASE_URL}/update`);
    console.log(`[${getTimestamp()}] Update response:`, updateResponse.data);

    // Wait before next batch
    console.log(`[${getTimestamp()}] Waiting 30 seconds before next batch...`);
    await new Promise((resolve) => setTimeout(resolve, WAIT_TIME_AFTER_UPDATE));
  } catch (error) {
    console.error(`[${getTimestamp()}] Error processing batch:`, batch);
    console.error(`[${getTimestamp()}] Error message:`, error.message);
    console.error(`[${getTimestamp()}] Error details:`, error.response?.data || error);
  }
}

// Function to sync reports from S3 (Redacted S3 bucket name)
function syncS3() {
  console.log(`[${getTimestamp()}] Syncing reports from S3...`);
  exec(
    'aws s3 sync s3://your-s3-bucket/reports/ ./Reports',
    (error, stdout, stderr) => {
      if (error) {
        console.error(`[${getTimestamp()}] Error syncing S3:`, error.message);
        return;
      }
      if (stderr) {
        console.error(`[${getTimestamp()}] S3 Sync STDERR:`, stderr);
      }
      console.log(`[${getTimestamp()}] S3 Sync completed. Output:`, stdout);
    }
  );
}

// Main function to process all batches
async function processAllBatches() {
  console.log(`[${getTimestamp()}] Calculating estimated total processing time...`);
  const estimatedTime = calculateEstimatedTime();
  console.log(`[${getTimestamp()}] Estimated total processing time: ${estimatedTime} minutes`);

  const batches = [];
  for (let i = 0; i < merchantIds.length; i += BATCH_SIZE) {
    batches.push(merchantIds.slice(i, i + BATCH_SIZE));
  }

  for (const batch of batches) {
    await processBatch(batch);
  }

  console.log(`[${getTimestamp()}] All batches have been processed!`);
  syncS3(); // Sync reports after batch processing
}

// Start the process
processAllBatches();
