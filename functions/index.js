const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

// When a TV session doc gets a uid written to it, generate a custom token
exports.mintTVToken = onDocumentUpdated("tvSessions/{sessionCode}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // Only act when uid is newly set and customToken not yet written
  if (!after.uid || after.customToken || before.uid === after.uid) return;

  // Check session isn't expired (10 min window)
  const created = after.createdAt?.toMillis?.() ?? 0;
  if (Date.now() - created > 10 * 60 * 1000) {
    await event.data.after.ref.update({ status: "expired" });
    return;
  }

  const customToken = await getAuth().createCustomToken(after.uid);
  await event.data.after.ref.update({ customToken, status: "authenticated" });
});
