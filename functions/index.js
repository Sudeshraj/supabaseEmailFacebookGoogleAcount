/**
 * Firebase Functions using Admin SDK (v2 format)
 */

const { setGlobalOptions } = require("firebase-functions");
const { onCall } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

// 🔥 Admin SDK Import
const admin = require("firebase-admin");

// 🔥 Initialize Admin SDK (MUST HAVE)
admin.initializeApp();

// Limit cost
setGlobalOptions({ maxInstances: 10 });

/**
 * 🔥 deleteUserByUid Cloud Function
 * Callable from Flutter
 * Deletes Firestore user doc + Auth user
 */
exports.deleteUserByUid = onCall(async (request) => {
  const uid = request.data.uid;

  if (!uid) {
    return {
      success: false,
      error: "UID is required",
    };
  }

  try {
    // 1️⃣ Delete Firestore document
    await admin.firestore().collection("users").doc(uid).delete().catch(() => {});

    // 2️⃣ Delete Auth User
    await admin.auth().deleteUser(uid);

    return { success: true };
  } catch (e) {
    logger.error("Delete Error:", e);
    return {
      success: false,
      error: e.toString(),
    };
  }
});
