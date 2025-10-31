// functions/src/index.ts

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

// Inicializa Admin SDK (una sola vez)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// =====================
// Configuración general
// =====================
const CONFIG = {
  REGION: "europe-west1",

  // Bot de soporte
  SUPPORT_BOT_ID: "26CSxWS7R7eZlrvXUV1qJFyL7Oc2",
  SUPPORT_BOT_NAME: "Soporte",

  // Umbrales de auto-moderación basados en agregados de reportes
  THRESHOLD_REVIEW: 1,   // ajusta a tus valores reales
  THRESHOLD_HIDDEN: 3,   // ajusta a tus valores reales

  // Auto-ocultar contenido por reportes
  AUTO_HIDE_FOR_CONTENT: true,

  // (Opcional) ocultar el chat directo del reportante con el autor
  ALSO_HIDE_DIRECT_ON_CONTENT_REPORT: false,
};

// ===================================================
// Helper: respeta el bloqueo de moderación manual
// ===================================================
function autoModerationDisabledFor(data: any): boolean {
  try {
    return data?.autoModerationDisabled === true
      || data?.moderation?.locked === true
      || data?.moderation?.mode === "manual";
  } catch {
    return false;
  }
}

/**
 * Allowlist de admin: pasa si
 *  - custom claim {admin:true}  Ó
 *  - email termina en @spotitfly.com Ó
 *  - existe en Firestore: admins/{uid}.active == true
 */
async function isSupportAdmin(auth: functions.https.CallableContext["auth"]): Promise<boolean> {
  if (!auth) return false;

  const isAdminClaim = (auth.token && (auth.token as any).admin) === true;
  const email = (auth.token && (auth.token as any).email) ? String((auth.token as any).email).toLowerCase() : "";
  const allowedEmail = email.endsWith("@spotitfly.com");
  if (isAdminClaim || allowedEmail) return true;

  try {
    const uid = auth.uid;
    const snap = await db.collection("admins").doc(uid).get();
    if (snap.exists) {
      const data = snap.data() || {};
      return data.active === true;
    }
  } catch {
    // ignore
  }
  return false;
}

// ===================================================
// Callable: enviar mensaje COMO BOT en un chat de soporte
// ===================================================
export const sendSupportAsBot = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const auth = context.auth;
    if (!auth) {
      throw new functions.https.HttpsError("unauthenticated", "Auth requerida.");
    }
    const allowed = await isSupportAdmin(auth);
    if (!allowed) {
      throw new functions.https.HttpsError("permission-denied", "Solo admin/support.");
    }

    const adminUid = auth.uid;
    const chatId = String(data?.chatId || "");
    const text = String(data?.text || "").trim();
    if (!chatId || !text) {
      throw new functions.https.HttpsError("invalid-argument", "chatId y text requeridos.");
    }

    const now = admin.firestore.Timestamp.now();
    const chatRef = db.collection("chats").doc(chatId);
    const msgRef = chatRef.collection("messages").doc();

    await msgRef.set({
      id: msgRef.id,
      chatId,
      senderId: CONFIG.SUPPORT_BOT_ID,
      senderName: CONFIG.SUPPORT_BOT_NAME, // 👈 nombre del bot
      type: "text",
      text,
      createdAt: now,
      system: false,
      meta: { byAdminUid: adminUid }, // auditoría
    });

    await chatRef.set(
      {
        lastMessage: text,
        lastSenderId: CONFIG.SUPPORT_BOT_ID,
        updatedAt: now,
      },
      { merge: true }
    );

    return { ok: true, id: msgRef.id };
  });

// ===================================================
// Callable: Moderación manual (spots y comentarios)
//  - fija locked + autoModerationDisabled
// ===================================================
export const adminModerate = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const auth = context.auth;
    if (!auth) {
      throw new functions.https.HttpsError("unauthenticated", "Auth requerida.");
    }
    const allowed = await isSupportAdmin(auth);
    if (!allowed) {
      throw new functions.https.HttpsError("permission-denied", "Solo admin/support.");
    }

    const adminUid = auth.uid;
    const kind = String(data?.kind || "");
    const reason = String(data?.reason || "manual");
    const now = admin.firestore.Timestamp.now();

    if (kind === "spot") {
      const spotId = String(data?.spotId || "");
      const state = String(data?.state || "review"); // "public" | "hidden" | "review"
      if (!spotId) {
        throw new functions.https.HttpsError("invalid-argument", "spotId requerido.");
      }

      const spotRef = db.collection("spots").doc(spotId);
      const patch: any = {
        updatedAt: now,
        moderation: {
          state,
          reason,
          by: adminUid,
          at: now,
          mode: "manual",
          locked: true,
        },
        autoModerationDisabled: true,
      };
      if (state === "hidden") patch.visibility = "hidden";
      if (state === "public") patch.visibility = "public";

      await spotRef.set(patch, { merge: true });
      return { ok: true, spotId, state };
    }

    if (kind === "comment") {
      const spotId = String(data?.spotId || "");
      const commentId = String(data?.commentId || "");
      const status = String(data?.status || "hidden"); // "visible" | "hidden" | "deleted"
      if (!spotId || !commentId) {
        throw new functions.https.HttpsError("invalid-argument", "spotId y commentId requeridos.");
      }

      const commentRef = db
        .collection("spots").doc(spotId)
        .collection("comments").doc(commentId);

      const patch: any = {
        updatedAt: now,
        moderation: {
          status,
          reason,
          by: adminUid,
          at: now,
          mode: "manual",
          locked: true,
        },
        autoModerationDisabled: true,
      };

      if (status === "deleted") {
        patch.deleted = true;
        patch.visibility = "hidden";
      } else if (status === "hidden") {
        patch.visibility = "hidden";
        patch.deleted = false;
      } else if (status === "visible") {
        patch.visibility = "public";
        patch.deleted = false;
      }

      await commentRef.set(patch, { merge: true });
      return { ok: true, spotId, commentId, status };
    }

    throw new functions.https.HttpsError("invalid-argument", "kind inválido (usa 'spot' o 'comment').");
  });

// ===================================================
// Trigger: al crear un reporte, auto-moderación que
//          respeta el lock/manual del admin
// ===================================================
export const onReportCreated = functions
  .region(CONFIG.REGION)
  .firestore.document("reports/{reportId}")
  .onCreate(async (snap: functions.firestore.DocumentSnapshot, _context: functions.EventContext) => {
    const data = snap.data() || {};
    const type = String(data.type || "");
    const reporterId = String(data.reporterId || "");
    const reason = String(data.reason || "report");
    const now = admin.firestore.Timestamp.now();

    // ===== SPOT =====
    if (type === "spot") {
      const spotId = String(data.targetId || data.spotId || "");
      if (!spotId) return;

      const spotRef = db.collection("spots").doc(spotId);
      const spotDoc = await spotRef.get();
      const spot = spotDoc.data() || {};

      // Si está bloqueado manualmente por admin, no tocar
      if (autoModerationDisabledFor(spot)) return;

      // Conteo de reportes agregados
      const aggDoc = await db.collection("reportAggregates").doc(`spot:${spotId}`).get();
      const count = (aggDoc.get("count") as number) ?? 0;

      if (CONFIG.AUTO_HIDE_FOR_CONTENT) {
        const patch: any = {
          updatedAt: now,
          moderation: {
            ...(spot.moderation || {}),
            reason,
            by: "system",
            at: now,
          },
        };

        if (count >= CONFIG.THRESHOLD_HIDDEN) {
          patch.visibility = "hidden";
          patch.moderation.state = "hidden";
          await spotRef.set(patch, { merge: true });
        } else if (count >= CONFIG.THRESHOLD_REVIEW) {
          patch.moderation.state = "review";
          await spotRef.set(patch, { merge: true });
        }
      }

      // (Opcional) ocultar chats directos reportante <-> autor
      if (CONFIG.ALSO_HIDE_DIRECT_ON_CONTENT_REPORT && reporterId) {
        const authorId = String(spot.authorId || spot.userId || "");
        if (authorId && authorId !== reporterId) {
          const qs = await db
            .collection("chats")
            .where("isSupport", "==", false)
            .where("participants", "array-contains", reporterId)
            .get();
          const batch = db.batch();
          qs.forEach((doc) => {
            const p = (doc.get("participants") as string[]) || [];
            if (p.includes(authorId)) {
              batch.set(
                doc.ref,
                { hiddenFor: admin.firestore.FieldValue.arrayUnion(reporterId) },
                { merge: true }
              );
            }
          });
          await batch.commit();
        }
      }
      return;
    }

    // ===== COMMENT =====
    if (type === "comment") {
      const spotId = String(data.spotId || "");
      const commentId = String(data.commentId || data.targetId || "");
      if (!spotId || !commentId) return;

      const commentRef = db
        .collection("spots").doc(spotId)
        .collection("comments").doc(commentId);
      const commentDoc = await commentRef.get();
      const comment = commentDoc.data() || {};

      if (autoModerationDisabledFor(comment)) return;

      const aggDoc = await db
        .collection("reportAggregates")
        .doc(`comment:${spotId}:${commentId}`)
        .get();
      const count = (aggDoc.get("count") as number) ?? 0;

      if (CONFIG.AUTO_HIDE_FOR_CONTENT) {
        const patch: any = {
          updatedAt: now,
          moderation: {
            ...(comment.moderation || {}),
            reason,
            by: "system",
            at: now,
          },
        };

        if (count >= CONFIG.THRESHOLD_HIDDEN) {
          patch.visibility = "hidden";
          patch.moderation.status = "hidden";
          await commentRef.set(patch, { merge: true });
        } else if (count >= CONFIG.THRESHOLD_REVIEW) {
          patch.moderation.status = "review";
          await commentRef.set(patch, { merge: true });
        }
      }
      return;
    }

    // ===== USER =====
    if (type === "user") {
      // No auto-bloqueamos usuarios a nivel global aquí.
      return;
    }
  });



// ============================================================================
// BEGIN INSERTS — Limpieza de reportes + agregados (SpotItFly)
// ============================================================================

/** Fuerza el agregado de un target concreto a count = value (p.ej. 0). */
async function setReportAggregate(docId: string, value: number, adminUid: string) {
  const now = admin.firestore.Timestamp.now();

  await db.collection("reportAggregates").doc(docId).set({
    count: value,
    lastClearedAt: now,
    lastClearedBy: adminUid,
    lastRecomputedAt: now,
    lastRecomputedBy: adminUid,
  }, { merge: true });
}

/** Recalcula el agregado de un target leyendo reports activos (no 'cleared'/'rejected'). */
async function recomputeReportAggregateForTarget(params: {
  type: "spot" | "comment" | "user",
  spotId?: string,
  commentId?: string,
  userId?: string,
  adminUid: string,
}) {
  const { type, spotId, commentId, userId, adminUid } = params;

  let q: FirebaseFirestore.Query<FirebaseFirestore.DocumentData>;
  let docId: string;

  if (type === "spot" && spotId) {
    docId = `spot:${spotId}`;
    q = db.collection("reports")
      .where("type", "==", "spot")
      .where("targetId", "==", spotId)
      .where("status", "in", ["open", "acted", "pending"]) as any;
  } else if (type === "comment" && spotId && commentId) {
    docId = `comment:${spotId}:${commentId}`;
    q = db.collection("reports")
      .where("type", "==", "comment")
      .where("spotId", "==", spotId)
      .where("commentId", "==", commentId)
      .where("status", "in", ["open", "acted", "pending"]) as any;
  } else if (type === "user" && userId) {
    docId = `user:${userId}`;
    q = db.collection("reports")
      .where("type", "==", "user")
      .where("targetId", "==", userId)
      .where("status", "in", ["open", "acted", "pending"]) as any;
  } else {
    return;
  }

  const snap = await q.get();
  const activeCount = snap.size || 0;
  await setReportAggregate(docId, activeCount, adminUid);
}

// -- Helpers de limpieza que fuerzan agregados a 0

async function clearReportsForSpot(spotId: string, adminUid: string) {
  if (!spotId) return;
  const now = admin.firestore.Timestamp.now();

  const q1 = await db.collection("reports")
    .where("type", "==", "spot")
    .where("targetId", "==", spotId)
    .get();

  const q2 = await db.collection("reports")
    .where("type", "==", "spot")
    .where("spotId", "==", spotId)
    .get();

  const seen = new Set<string>();
  const batch = db.batch();

  for (const snap of [q1, q2]) {
    snap.forEach(doc => {
      if (seen.has(doc.id)) return;
      seen.add(doc.id);
      batch.set(doc.ref, {
        status: "cleared",
        clearedAt: now,
        clearedBy: adminUid,
        processedAt: now,
      }, { merge: true });
    });
  }

  await batch.commit().catch(() => {});

  await setReportAggregate(`spot:${spotId}`, 0, adminUid);
}

async function clearReportsForComment(spotId: string, commentId: string, adminUid: string) {
  if (!spotId || !commentId) return;
  const now = admin.firestore.Timestamp.now();

  const q1 = await db.collection("reports")
    .where("type", "==", "comment")
    .where("spotId", "==", spotId)
    .where("commentId", "==", commentId)
    .get();

  const q2 = await db.collection("reports")
    .where("type", "==", "comment")
    .where("targetId", "==", commentId)
    .where("spotId", "==", spotId)
    .get();

  const seen = new Set<string>();
  const batch = db.batch();

  for (const snap of [q1, q2]) {
    snap.forEach(doc => {
      if (seen.has(doc.id)) return;
      seen.add(doc.id);
      batch.set(doc.ref, {
        status: "cleared",
        clearedAt: now,
        clearedBy: adminUid,
        processedAt: now,
      }, { merge: true });
    });
  }

  await batch.commit().catch(() => {});

  await setReportAggregate(`comment:${spotId}:${commentId}`, 0, adminUid);
}

async function clearReportsForUser(userId: string, adminUid: string) {
  if (!userId) return;
  const now = admin.firestore.Timestamp.now();

  const q = await db.collection("reports")
    .where("type", "==", "user")
    .where("targetId", "==", userId)
    .get();

  const batch = db.batch();
  q.forEach(doc => {
    batch.set(doc.ref, {
      status: "cleared",
      clearedAt: now,
      clearedBy: adminUid,
      processedAt: now,
    }, { merge: true });
  });

  await batch.commit().catch(() => {});

  await setReportAggregate(`user:${userId}`, 0, adminUid);
}

// -- Callable para desbloqueo de usuario que limpia reportes
export const adminUnblockUser = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const auth = context.auth;
    if (!auth) throw new functions.https.HttpsError("unauthenticated", "Auth requerida.");
    const allowed = await isSupportAdmin(auth);
    if (!allowed) throw new functions.https.HttpsError("permission-denied", "Solo admin/support.");

    const adminUid = auth.uid;
    const userId = String(data?.userId || data?.uid || "");
    if (!userId) throw new functions.https.HttpsError("invalid-argument", "Falta userId.");

    await clearReportsForUser(userId, adminUid);
    return { ok: true, userId };
  });

// -- Triggers: al volver a visibility:"public", limpiar reportes y dejar agregados a 0
export const onSpotBecamePublic = functions
  .region(CONFIG.REGION)
  .firestore.document("spots/{spotId}")
  .onUpdate(async (
    change: functions.Change<functions.firestore.DocumentSnapshot>,
    context: functions.EventContext
  ) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeVis = String(before.visibility || "");
    const afterVis = String(after.visibility || "");

    if (beforeVis !== "public" && afterVis === "public") {
      const spotId = context.params.spotId as string;
      const adminUid = String((after.moderation && after.moderation.by) || "system");
      await clearReportsForSpot(spotId, adminUid);
    }
  });

export const onCommentBecamePublic = functions
  .region(CONFIG.REGION)
  .firestore.document("spots/{spotId}/comments/{commentId}")
  .onUpdate(async (
    change: functions.Change<functions.firestore.DocumentSnapshot>,
    context: functions.EventContext
  ) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeVis = String(before.visibility || "");
    const afterVis = String(after.visibility || "");

    if (beforeVis !== "public" && afterVis === "public") {
      const spotId = context.params.spotId as string;
      const commentId = context.params.commentId as string;
      const adminUid = String((after.moderation && after.moderation.by) || "system");
      await clearReportsForComment(spotId, commentId, adminUid);
    }
  });

// -- Callables de recomputo defensivo (backfill / verificación)
export const adminRecomputeSpotAggregate = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const auth = context.auth;
    if (!auth) throw new functions.https.HttpsError("unauthenticated", "Auth requerida.");
    const allowed = await isSupportAdmin(auth);
    if (!allowed) throw new functions.https.HttpsError("permission-denied", "Solo admin/support.");

    const spotId = String(data?.spotId || "");
    if (!spotId) throw new functions.https.HttpsError("invalid-argument", "Falta spotId.");
    await recomputeReportAggregateForTarget({ type: "spot", spotId, adminUid: auth.uid });
    return { ok: true, docId: `spot:${spotId}` };
  });

export const adminRecomputeCommentAggregate = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const auth = context.auth;
    if (!auth) throw new functions.https.HttpsError("unauthenticated", "Auth requerida.");
    const allowed = await isSupportAdmin(auth);
    if (!allowed) throw new functions.https.HttpsError("permission-denied", "Solo admin/support.");

    const spotId = String(data?.spotId || "");
    const commentId = String(data?.commentId || "");
    if (!spotId || !commentId) throw new functions.https.HttpsError("invalid-argument", "Falta spotId/commentId.");
    await recomputeReportAggregateForTarget({ type: "comment", spotId, commentId, adminUid: auth.uid });
    return { ok: true, docId: `comment:${spotId}:${commentId}` };
  });

export const adminRecomputeUserAggregate = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const auth = context.auth;
    if (!auth) throw new functions.https.HttpsError("unauthenticated", "Auth requerida.");
    const allowed = await isSupportAdmin(auth);
    if (!allowed) throw new functions.https.HttpsError("permission-denied", "Solo admin/support.");

    const userId = String(data?.userId || "");
    if (!userId) throw new functions.https.HttpsError("invalid-argument", "Falta userId.");
    await recomputeReportAggregateForTarget({ type: "user", userId, adminUid: auth.uid });
    return { ok: true, docId: `user:${userId}` };
  });

// ============================================================================
// END INSERTS — Limpieza de reportes + agregados (SpotItFly)
// ============================================================================

// ============================================================================
// NOTIFICATIONS — Push para chats y comentarios + badge real
// ============================================================================

const f = functions.region(CONFIG.REGION);

// --- Idempotencia por usuario + evento ---
async function processedOnce(uid: string, key: string, work: () => Promise<void>) {
  // Marca: users/{uid}/meta/processed/keys/{key}
  const ref = db.collection("users").doc(uid)
    .collection("meta").doc("processed")
    .collection("keys").doc(key);

  // Transacción: si existe, ignoramos; si no, creamos y hacemos el trabajo
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) throw new Error("already-processed");
    tx.set(ref, { at: admin.firestore.FieldValue.serverTimestamp() });
  }).catch((e) => {
    if (String(e.message || "").includes("already-processed")) return;
    throw e;
  });

  await work();
}

// -----------------------------
// Helpers i18n y formato
// -----------------------------
function snippet(s?: string, max = 120): string {
  if (!s) return "";
  const t = s.replace(/\s+/g, " ").trim();
  return t.length <= max ? t : t.slice(0, max - 1) + "…";
}

// -----------------------------
// Helpers Firestore
// -----------------------------
type NotifPrefs = {
  enabled?: boolean;
  messages?: boolean;
  comments?: boolean;
  lang?: string;
};

async function getUserPrefs(uid: string): Promise<NotifPrefs> {
  const doc = await db.collection("users").doc(uid).collection("meta").doc("notifications").get();
  return (doc.exists ? (doc.data() as NotifPrefs) : {}) || {};
}

async function getUserDeviceTokens(uid: string) {
  const snap = await db.collection("users").doc(uid).collection("devices").get();
  const tokens: string[] = [];
  snap.forEach((d) => {
    tokens.push(d.id); // el docId es el token FCM
  });
  return { tokens };
}

// Per-chat preferences (mute/mentions) — soporta varias rutas y campos
type ChatPrefs = {
  mute?: boolean;           // preferido
  muted?: boolean;          // alias frecuente
  muteUntil?: admin.firestore.Timestamp | number; // silencio temporal
  notifications?: "all" | "mentions" | "none";
};

async function getChatPrefs(uid: string, chatId: string): Promise<ChatPrefs> {
  const base = db.collection("users").doc(uid).collection("meta");

  // 0) ✅ users/{uid}/meta/chatPrefs/prefs/{chatId}  ← la que usa tu app ahora mismo
  try {
    const d = await base.doc("chatPrefs").collection("prefs").doc(chatId).get();
    if (d.exists) return (d.data() as ChatPrefs) || {};
  } catch {}

  // 1) users/{uid}/meta/chatPrefs/threads/{chatId}
  try {
    const d = await base.doc("chatPrefs").collection("threads").doc(chatId).get();
    if (d.exists) return (d.data() as ChatPrefs) || {};
  } catch {}

  // 2) users/{uid}/meta/chatPrefs/byChat/{chatId}
  try {
    const d = await base.doc("chatPrefs").collection("byChat").doc(chatId).get();
    if (d.exists) return (d.data() as ChatPrefs) || {};
  } catch {}

  // 3) users/{uid}/meta/chatPrefs (doc plano) con mapa threads[chatId]
  try {
    const flat = await base.doc("chatPrefs").get();
    if (flat.exists) {
      const data = (flat.data() || {}) as any;
      const t = (data.threads || {}) as Record<string, any>;
      if (t[chatId]) return (t[chatId] as ChatPrefs) || {};
    }
  } catch {}

  // 4) users/{uid}/meta/chatPrefs_{chatId}
  try {
    const d = await base.doc(`chatPrefs_${chatId}`).get();
    if (d.exists) return (d.data() as ChatPrefs) || {};
  } catch {}

  // 5) users/{uid}/meta/chatPrefs/{chatId} (legacy subcol)
  try {
    const d = await base.doc("chatPrefs").collection(chatId).limit(1).get();
    if (!d.empty) return (d.docs[0].data() as ChatPrefs) || {};
  } catch {}

  return {};
}


async function sendToTokens(
  tokens: string[],
  payload: Omit<admin.messaging.MulticastMessage, "tokens">
) {
  if (tokens.length === 0) return;
  const res = await admin.messaging().sendEachForMulticast({ ...payload, tokens });

  // Limpia tokens inválidos
  const toDelete: string[] = [];
  res.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error?.code || "";
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
        toDelete.push(tokens[i]);
      }
    }
  });

  if (toDelete.length) {
    // Busca y borra esos tokens en cualquier users/*/devices/*
    const cg = await db.collectionGroup("devices")
      .where(admin.firestore.FieldPath.documentId(), "==", toDelete[0]).get();
    const batch = db.batch();
    cg.forEach((ref) => batch.delete(ref.ref));
    await batch.commit().catch(() => {});
    // Best-effort para el resto
    for (let i = 1; i < toDelete.length; i++) {
      const cg2 = await db.collectionGroup("devices")
        .where(admin.firestore.FieldPath.documentId(), "==", toDelete[i]).get();
      const b2 = db.batch();
      cg2.forEach((ref) => b2.delete(ref.ref));
      await b2.commit().catch(() => {});
    }
  }
}

function buildIOSPayload(
  title: string,
  body: string,
  link: string,
  collapseId: string,
  badge: number
): Omit<admin.messaging.MulticastMessage, "tokens"> {
  return {
    notification: { title, body },   // Android; en iOS manda APNs
    data: { link },                  // AppDelegate usa "link" -> deeplink spots://...
    apns: {
      headers: {
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": collapseId,
      },
      payload: {
        aps: {
          alert: { title, body },
          sound: "default",
          badge,
        },
      },
    },
  };
}

function buildIOSBadgeOnly(badge: number): Omit<admin.messaging.MulticastMessage, "tokens"> {
  return {
    apns: {
      headers: {
        "apns-push-type": "background",
        "apns-priority": "5"
      },
      payload: {
        aps: {
          "content-available": 1,
          badge
        }
      }
    }
  };
}


// -----------------------------
// Badge y contadores
// -----------------------------
async function recomputeBadge(uid: string): Promise<number> {
  const cRef = db.collection("users").doc(uid).collection("meta").doc("counters");
  const cSnap = await cRef.get();
  const c = cSnap.exists ? cSnap.data()! : {};
  const unreadChats = Number(c.unreadChats || 0);
  const unreadSpotComments = Number(c.unreadSpotComments || 0);
  const badge = unreadChats + unreadSpotComments;
  await cRef.set({ unreadChats, unreadSpotComments, badge }, { merge: true });
  return badge;
}

async function incThreadAndTotals(uid: string, type: "chat" | "spot", threadId: string): Promise<number> {
  const threadCol = type === "chat" ? "chatCounters" : "spotCounters";
  const countersDoc = type === "chat" ? "unreadChats" : "unreadSpotComments";

  const batch = db.batch();
  const tRef = db.collection("users").doc(uid).collection("meta").doc(threadCol)
    .collection("threads").doc(threadId);
  batch.set(tRef, { unread: admin.firestore.FieldValue.increment(1) }, { merge: true });

  const cRef = db.collection("users").doc(uid).collection("meta").doc("counters");
  batch.set(cRef, { [countersDoc]: admin.firestore.FieldValue.increment(1) }, { merge: true });

  await batch.commit();
  return recomputeBadge(uid);
}

async function resetThreadAndTotals(uid: string, type: "chat" | "spot", threadId: string): Promise<void> {
  const threadCol = type === "chat" ? "chatCounters" : "spotCounters";
  const countersDoc = type === "chat" ? "unreadChats" : "unreadSpotComments";

  const tRef = db.collection("users").doc(uid).collection("meta").doc(threadCol)
    .collection("threads").doc(threadId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(tRef);
    const unread = Number(snap.exists ? (snap.data()?.unread || 0) : 0);
    tx.set(tRef, { unread: 0 }, { merge: true });

    if (unread > 0) {
      const cRef = db.collection("users").doc(uid).collection("meta").doc("counters");
      tx.set(cRef, { [countersDoc]: admin.firestore.FieldValue.increment(-unread) }, { merge: true });
    }
  });
  await recomputeBadge(uid);
}

// -----------------------------
// A) Nuevo MENSAJE en chat
// -----------------------------
export const onMessageCreate = f.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap: functions.firestore.DocumentSnapshot, ctx: functions.EventContext) => {
    const { chatId } = ctx.params;
    const msg = snap.data() || {};
    const senderId: string = msg.senderId;
    const text: string = msg.text || "";
      
      const mentions: string[] = Array.isArray(msg.mentions)
        ? msg.mentions.filter((x: any) => typeof x === "string" && x)
        : [];

    // Resolver nombre del remitente
    let senderName: string | undefined = msg.senderName;

    if (!senderName) {
      try {
        const uDoc = await db.collection("users").doc(senderId).get();
        const u = uDoc.data() || {};
        senderName =
          u.username ||
          u.displayName ||
          u.name ||
          (u.email ? String(u.email).split("@")[0] : undefined);
      } catch {
        // noop
      }
    }

    // Fallbacks finales (incluye bot)
    if (!senderName) {
      senderName = (senderId === CONFIG.SUPPORT_BOT_ID)
        ? CONFIG.SUPPORT_BOT_NAME
        : "Alguien";
    }

    // Backfill al documento del mensaje (no re-dispara onCreate)
    if (!msg.senderName && senderName) {
      await snap.ref.set({ senderName }, { merge: true });
    }

    // Leemos el chat una sola vez para metadata (nombre, participantes)
    const chatDoc = await db.collection("chats").doc(chatId).get();
    const chatData: any = chatDoc.exists ? chatDoc.data() : {};
    const participants: string[] = (chatData?.participants || []).filter(Boolean);
    const recipients = participants.filter((u) => u !== senderId);
    if (recipients.length === 0) return;

    // Precalcular si es grupo
    const parts = (chatData?.participants || participants) || [];
    const isGroup = (chatData?.type === "group") || (Array.isArray(parts) && parts.length > 2);
    const chatName: string | undefined = chatData?.name;

    await Promise.all(
      recipients.map(async (uid) => {
        const prefs = await getUserPrefs(uid);
        const enabled = prefs.enabled ?? true;
        const allow = prefs.messages ?? true;
        if (!enabled || !allow) return;

        // Obtener prefs por chat y tokens del usuario
        const [chatPrefs, { tokens }] = await Promise.all([
          getChatPrefs(uid, chatId),
          getUserDeviceTokens(uid),
        ]);
        if (tokens.length === 0) return;

        const key = `msg:${chatId}:${snap.id}`;
        await processedOnce(uid, key, async () => {
          // SIEMPRE incrementamos contadores y badge (mute no bloquea contadores)
          const badge = await incThreadAndTotals(uid, "chat", chatId);

            const isMentioned = mentions.includes(uid);

            // Preferencia "Solo menciones": si no te mencionan -> badge-only; si te mencionan -> seguimos a alerta normal (aunque esté muteado)
            if (chatPrefs?.notifications === "mentions") {
              if (!isMentioned) {
                const bg = buildIOSBadgeOnly(badge);
                await sendToTokens(tokens, bg);
                return;
              }
            // Si está mencionado, no retornamos: continuamos a preparar alerta normal
            } else if (chatPrefs?.mute === true || chatPrefs?.notifications === "none") {
              // Mute o none -> badge-only
              const bg = buildIOSBadgeOnly(badge);
              await sendToTokens(tokens, bg);
              return;
            }

            // No mute/none, o "mentions" con mención -> alerta normal


          // No mute -> alerta normal
          let title: string;
          let body: string;

          if (isGroup) {
            title = chatName || "Grupo";
            body = (senderName ? (senderName + ": ") : "") + snippet(text, 120);
          } else {
            title = senderName!;
            body = snippet(text, 120);
          }

          const payload = buildIOSPayload(
            title,
            body,
            `spots://chat/${chatId}`,
            `chat_${chatId}`,
            badge
          );
          await sendToTokens(tokens, payload);
        });
      })
    );
  });

// -----------------------------
// B) Nuevo COMENTARIO en spot
// -----------------------------
export const onCommentCreate = f.firestore
  .document("spots/{spotId}/comments/{commentId}")
  .onCreate(async (snap: functions.firestore.DocumentSnapshot, ctx: functions.EventContext) => {
    const { spotId } = ctx.params;
    const cmt = snap.data() || {};
    const authorId: string = cmt.authorId;
    let authorName: string = cmt.authorName || "";

    // Resolver nombre del autor si falta
    if (!authorName && authorId) {
      try {
        const uDoc = await db.collection("users").doc(authorId).get();
        const u = uDoc.data() || {};
        authorName =
          u.username ||
          u.displayName ||
          u.name ||
          (u.email ? String(u.email).split("@")[0] : "Alguien");
      } catch {
        authorName = "Alguien";
      }
      // Backfill opcional
      await snap.ref.set({ authorName }, { merge: true }).catch(() => {});
    }

    const text: string = cmt.text || "";

    const spotDoc = await db.collection("spots").doc(spotId).get();
    const owner: string | undefined = spotDoc.data()?.createdBy;
    if (!owner || owner === authorId) return;

    const prefs = await getUserPrefs(owner);
    const enabled = prefs.enabled ?? true;
    const allow = prefs.comments ?? true;
    if (!enabled || !allow) return;

    const { tokens } = await getUserDeviceTokens(owner);
    if (tokens.length === 0) return;

    const key = `cmt:${spotId}:${snap.id}`;
    const spotTitle: string = String(spotDoc.data()?.name || spotDoc.data()?.title || "tu Spot");

    await processedOnce(owner, key, async () => {
      const badge = await incThreadAndTotals(owner, "spot", spotId);

      // Título: "Nuevo comentario en tu Spot: <nombre>"
      // Cuerpo: "username: texto recortado"
      const title = `Nuevo comentario en tu Spot: ${spotTitle}`;
      const body = `${authorName}: ${snippet(text, 120)}`;

      const payload = buildIOSPayload(title, body, `spots://spot/${spotId}`, `spot_${spotId}`, badge);
      await sendToTokens(tokens, payload);
    });
  });

// -----------------------------
// C) Lectura de CHAT -> reset hilo + badge
// -----------------------------
export const onChatReadWrite = f.firestore
  .document("users/{uid}/chatsReads/{chatId}")
  .onWrite(async (_change, ctx) => {
    const { uid, chatId } = ctx.params;
    await resetThreadAndTotals(uid, "chat", chatId);

    const badge = await recomputeBadge(uid);
    const { tokens } = await getUserDeviceTokens(uid);
    if (tokens.length) {
      await sendToTokens(tokens, buildIOSBadgeOnly(badge));
    }
  });

// -----------------------------
// D) Apertura de SPOT (owner) -> reset hilo + badge
// -----------------------------
export const onSpotReadWrite = f.firestore
  .document("users/{uid}/spotReads/{spotId}")
  .onWrite(async (_change, ctx) => {
    const { uid, spotId } = ctx.params;
    await resetThreadAndTotals(uid, "spot", spotId);
    const badge = await recomputeBadge(uid);

    const { tokens } = await getUserDeviceTokens(uid);
    if (tokens.length) {
      await sendToTokens(tokens, buildIOSBadgeOnly(badge));
    }
  });

// ===================================================
// Groups (MVP) — non-destructive callables
// ===================================================
type CreateGroupInput = { name: string; memberIds: string[]; photoURL?: string };
function uniq(a: string[]): string[] { return Array.from(new Set(a.filter(Boolean))); }

// Helpers: obtener username(s) desde users/{uid}
async function fetchUsername(uid: string): Promise<string> {
  try {
    const doc = await db.collection("users").doc(uid).get();
    const d = doc.data() || {};
    const username = String(d.username || "").trim();
    const fallback = String(d.displayName || d.name || d.fullName || "").trim();
    return username ? `@${username}` : (fallback || "Usuario");
  } catch {
    return "Usuario";
  }
}


async function fetchUsernames(uids: string[]): Promise<string[]> {
  return Promise.all(uids.map(fetchUsername));
}

export const createGroup = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: CreateGroupInput, context) => {
    const auth = context.auth;
    if (!auth || !auth.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const owner = auth.uid;
    const name = (data?.name || "").trim();
    if (!name) throw new functions.https.HttpsError("invalid-argument", "name requerido");
    const memberIds = uniq([owner, ...(Array.isArray(data?.memberIds) ? data.memberIds : [])]);
    if (memberIds.length < 2) throw new functions.https.HttpsError("invalid-argument", "mínimo 2 miembros");

      const now = admin.firestore.FieldValue.serverTimestamp();
      const chatRef = db.collection("chats").doc();
      await chatRef.set({
        type: "group",
        name,
        photoURL: data?.photoURL || null,
        participants: memberIds,
        createdAt: now,
        createdBy: owner,
        ownerId: owner,           // 🆕 owner explícito
        admins: [],               // 🆕 lista de admins
        updatedAt: now,
        membersCount: memberIds.length,
        lastMessage: "Grupo creado",
        lastSenderId: owner,
      }, { merge: true });


    // Mensaje de sistema con los invitados iniciales (excluye al owner)
const invited = memberIds.filter((u) => u !== owner);
if (invited.length) {
  const actorName = await fetchUsername(owner);
  const addedNames = await fetchUsernames(invited);
  const addedText =
    addedNames.length === 1
      ? `${actorName} añadió a ${addedNames[0]}`
      : `${actorName} añadió a ${addedNames.join(", ")}`;

  await chatRef.collection("messages").add({
    text: addedText,
    system: true,
    senderId: owner,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}


    return { ok: true, chatId: chatRef.id };

  });

export const addMembers = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string; memberIds: string[] }, context) => {
    const auth = context.auth;
    if (!auth || !auth.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const { chatId } = data || {};
    const chatRef = db.collection("chats").doc(String(chatId || ""));
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");

    const c = snap.data() || {};
    const me = auth.uid;
    const parts: string[] = (c.participants || []).filter(Boolean);
    if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");

    const newMembers = uniq(Array.isArray(data?.memberIds) ? data.memberIds : []);
    const final = uniq(parts.concat(newMembers));
    if (final.length === parts.length) return { ok: true, chatId }; // nada que hacer

    await chatRef.set({
      participants: final,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      membersCount: final.length,
      type: c.type || (final.length > 2 ? "group" : "direct"),
    }, { merge: true });

        const actorName = await fetchUsername(me);
const addedNames = await fetchUsernames(newMembers);
const addedText =
  addedNames.length === 1
    ? `${actorName} añadió a ${addedNames[0]}`
    : `${actorName} añadió a ${addedNames.join(", ")}`;

await chatRef.collection("messages").add({
  text: addedText,
  system: true,
  senderId: me,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
});




    return { ok: true, chatId };
  });

export const removeMember = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string; uid: string }, context) => {
    const auth = context.auth;
    if (!auth || !auth.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const { chatId, uid } = data || {};
    if (!chatId || !uid) throw new functions.https.HttpsError("invalid-argument", "Parámetros");

    const chatRef = db.collection("chats").doc(chatId);
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
    const c = snap.data() || {};
    const me = auth.uid;
    const parts: string[] = (c.participants || []).filter(Boolean);
    if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");
    const final = parts.filter((p) => p !== uid);
    await chatRef.set({
      participants: final,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      membersCount: final.length,
      type: c.type || (final.length > 2 ? "group" : "direct"),
    }, { merge: true });

    const actorName = await fetchUsername(me);
const removedName = await fetchUsername(uid);

await chatRef.collection("messages").add({
  text: `${actorName} eliminó a ${removedName}`,
  system: true,
  senderId: me,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
});


    return { ok: true, chatId };
  });

export const leaveGroup = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string }, context) => {
    const auth = context.auth;
    if (!auth || !auth.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const { chatId } = data || {};
    const me = auth.uid;
    const chatRef = db.collection("chats").doc(String(chatId || ""));
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
      const c = snap.data() || {};
      const parts: string[] = (c.participants || []).filter(Boolean);
      if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");

      const final = parts.filter((p) => p != me);

      // 🆕 Transferencia si el que se va es el owner
      const ownerId: string = String(c.ownerId || c.createdBy || "");
      const admins: string[] = Array.isArray(c.admins) ? c.admins.filter(Boolean) : [];
      let newOwnerId = ownerId;
      let newAdmins = admins.slice();

      if (me === ownerId) {
        const remaining = final;
        // Preferencia: primer admin que siga en el grupo
        const adminCandidate = admins.find((a) => remaining.includes(a));
        if (adminCandidate) {
          newOwnerId = adminCandidate;
          newAdmins = admins.filter((a) => a !== adminCandidate); // el nuevo owner sale de admins
        } else if (remaining.length > 0) {
          newOwnerId = remaining[0]; // miembro más antiguo (orden actual)
        } else {
          newOwnerId = ""; // grupo vacío → sin owner
        }
      }

      await chatRef.set({
        participants: final,
        membersCount: final.length,
        type: c.type || (final.length > 2 ? "group" : "direct"),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(me === ownerId ? { ownerId: newOwnerId, admins: newAdmins } : {}),
      }, { merge: true });

      await chatRef.collection("messages").add({
        text: `salió del grupo`,
        system: true,
        senderId: me,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (me === ownerId && newOwnerId && newOwnerId !== ownerId) {
        await chatRef.collection("messages").add({
          text: `transferió la propiedad del grupo`,
          system: true,
          senderId: me,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          meta: { to: newOwnerId },
        });
      }

      return { ok: true, chatId };

  });

export const renameGroup = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string; name: string }, context) => {
    const auth = context.auth;
    if (!auth || !auth.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const { chatId, name } = data || {};
    const me = auth.uid;
    const chatRef = db.collection("chats").doc(String(chatId || ""));
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
    const c = snap.data() || {};
    const parts: string[] = (c.participants || []).filter(Boolean);
    if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");
    const newName = (name || "").trim();
    if (!newName) throw new functions.https.HttpsError("invalid-argument", "name requerido");

    await chatRef.set({
      name: newName,
      type: "group",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await chatRef.collection("messages").add({
      text: `cambió el nombre del grupo a “${newName}”`,
      system: true,
      senderId: me,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, chatId };
  });

export const setGroupPhoto = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string; photoURL: string }, context) => {
    const auth = context.auth;
    if (!auth || !auth.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const { chatId, photoURL } = data || {};
    const me = auth.uid;
    const chatRef = db.collection("chats").doc(String(chatId || ""));
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
    const c = snap.data() || {};
    const parts: string[] = (c.participants || []).filter(Boolean);
    if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");
    const u = (photoURL || "").trim();
    if (!u) throw new functions.https.HttpsError("invalid-argument", "photoURL requerido");

    await chatRef.set({
      photoURL: u,
      type: "group",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await chatRef.collection("messages").add({
      text: `actualizó la foto del grupo`,
      system: true,
      senderId: me,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, chatId };
  });

// ============================================================================
// Invitaciones a grupo + Límite de miembros
// ============================================================================

const INVITES_COLLECTION = "groupInvites";
const DEFAULT_GROUP_LIMIT = Number(process.env.GROUP_LIMIT || 64);

function groupLimitOf(chat: FirebaseFirestore.DocumentData | undefined): number {
  const v = Number(chat?.maxMembers);
  if (Number.isFinite(v) && v > 0) return v;
  return DEFAULT_GROUP_LIMIT;
}

function isAdminOrOwner(me: string, chat: any): boolean {
  const ownerId = String(chat?.ownerId || chat?.createdBy || "");
  const admins: string[] = Array.isArray(chat?.admins) ? chat.admins.filter(Boolean) : [];
  return me === ownerId || admins.includes(me);
}

function randomCode(len = 8): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < len; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

// Crea (o devuelve si ya hay una activa) una invitación al grupo
export const createInviteLink = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string }, context) => {
    const auth = context.auth;
    if (!auth?.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const me = auth.uid;
    const chatId = String(data?.chatId || "").trim();
    if (!chatId) throw new functions.https.HttpsError("invalid-argument", "chatId requerido");

    const chatRef = db.collection("chats").doc(chatId);
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
    const chat = snap.data() || {};
    const parts: string[] = (chat.participants || []).filter(Boolean);
    if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");
    if (!isAdminOrOwner(me, chat)) throw new functions.https.HttpsError("permission-denied", "Solo admin/owner");

    // Si ya hay una activa para este chat, reutilizamos
    const existing = await db.collection(INVITES_COLLECTION)
      .where("chatId", "==", chatId)
      .where("active", "==", true)
      .limit(1)
      .get();

    if (!existing.empty) {
      const doc = existing.docs[0];
      const code = doc.id;
      return { ok: true, code, url: `spots://invite/${code}` };
    }

    // Generar código único
    let code = randomCode(8);
    for (let i = 0; i < 5; i++) {
      const test = await db.collection(INVITES_COLLECTION).doc(code).get();
      if (!test.exists) break;
      code = randomCode(8);
    }

    const now = admin.firestore.Timestamp.now();
    await db.collection(INVITES_COLLECTION).doc(code).set({
      chatId,
      createdBy: me,
      createdAt: now,
      active: true,
      uses: 0,
    });

    return { ok: true, code, url: `spots://invite/${code}` };
  });

// Revoca la invitación activa (si existe)
export const revokeInviteLink = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string }, context) => {
    const auth = context.auth;
    if (!auth?.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const me = auth.uid;
    const chatId = String(data?.chatId || "").trim();
    if (!chatId) throw new functions.https.HttpsError("invalid-argument", "chatId requerido");

    const chatRef = db.collection("chats").doc(chatId);
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
    const chat = snap.data() || {};
    const parts: string[] = (chat.participants || []).filter(Boolean);
    if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");
    if (!isAdminOrOwner(me, chat)) throw new functions.https.HttpsError("permission-denied", "Solo admin/owner");

    const existing = await db.collection(INVITES_COLLECTION)
      .where("chatId", "==", chatId)
      .where("active", "==", true)
      .limit(1)
      .get();

    if (existing.empty) return { ok: true, revoked: false };

    await existing.docs[0].ref.set({ active: false, revokedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return { ok: true, revoked: true };
  });

// Consulta meta de una invitación sin desvelar datos sensibles del chat
export const getInviteMeta = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { code: string }, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Auth requerida.");
    }
    const code = String(data?.code || "").trim().toUpperCase();
    if (!code) {
      throw new functions.https.HttpsError("invalid-argument", "code requerido.");
    }

    const inviteRef = db.collection("groupInvites").doc(code);
    const inviteSnap = await inviteRef.get();
    if (!inviteSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Invitación no existe");
    }
    const invite = inviteSnap.data() || {};
    if (invite.active === false) {
      throw new functions.https.HttpsError("failed-precondition", "Invitación revocada");
    }

    const chatId: string = String(invite.chatId || "");
    if (!chatId) {
      throw new functions.https.HttpsError("internal", "Invitación corrupta");
    }

    // Leemos el chat y devolvemos solo campos inocuos
    const chatSnap = await db.collection("chats").doc(chatId).get();
    if (!chatSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Chat no existe");
    }
    const chat = chatSnap.data() || {};
    const name: string = String(chat.name || chat.displayName || "Grupo").trim();
    const photoURL: string | null = chat.photoURL ? String(chat.photoURL) : null;

    return { ok: true, name, photoURL, chatId };
  });


// Unirse por código de invitación (respeta límite de miembros)
export const joinByInvite = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { code: string }, context) => {
    const auth = context.auth;
    if (!auth?.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const me = auth.uid;
    const code = String(data?.code || "").trim().toUpperCase();
    if (!code) throw new functions.https.HttpsError("invalid-argument", "code requerido");

    const inviteRef = db.collection(INVITES_COLLECTION).doc(code);
    const inviteSnap = await inviteRef.get();
    if (!inviteSnap.exists) throw new functions.https.HttpsError("not-found", "Invitación no existe");
    const invite = inviteSnap.data() || {};
    if (invite.active === false) throw new functions.https.HttpsError("failed-precondition", "Invitación revocada");

    const chatId: string = String(invite.chatId || "");
    if (!chatId) throw new functions.https.HttpsError("internal", "Invitación corrupta");

    const chatRef = db.collection("chats").doc(chatId);

    await db.runTransaction(async (tx) => {
      const cSnap = await tx.get(chatRef);
      if (!cSnap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
      const chat = cSnap.data() || {};
      const parts: string[] = (chat.participants || []).filter(Boolean);
      const limit = groupLimitOf(chat);

      if (parts.includes(me)) return; // idempotente

      if (parts.length >= limit) {
        throw new functions.https.HttpsError("resource-exhausted", `El grupo está completo (${limit} miembros)`);
      }

      const next = Array.from(new Set([...parts, me]));
      tx.set(chatRef, {
        participants: next,
        membersCount: next.length,
        type: "group",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessage: "se unió al grupo",
        lastSenderId: me,
      }, { merge: true });

      const msgRef = chatRef.collection("messages").doc();
      tx.set(msgRef, {
        id: msgRef.id,
        chatId,
        senderId: me,
        text: "se unió al grupo",
        system: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.set(inviteRef, { uses: admin.firestore.FieldValue.increment(1) }, { merge: true });
    });

    return { ok: true, chatId };
  });

// (Opcional) addMembers con límite server-side sin tocar tu addMembers actual
export const addMembersWithLimit = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string; userIds: string[] }, context) => {
    const auth = context.auth;
    if (!auth?.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const me = auth.uid;
    const chatId = String(data?.chatId || "");
    const toAdd = Array.isArray(data?.userIds) ? data.userIds.filter(Boolean) : [];
    if (!chatId || toAdd.length === 0) throw new functions.https.HttpsError("invalid-argument", "chatId/userIds");

    const chatRef = db.collection("chats").doc(chatId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(chatRef);
      if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
      const c = snap.data() || {};
      const parts: string[] = Array.isArray(c.participants) ? c.participants.filter(Boolean) : [];
      if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");
      if (!isAdminOrOwner(me, c)) throw new functions.https.HttpsError("permission-denied", "Solo admin/owner");

      const limit = groupLimitOf(c);
      const unique = toAdd.filter((u) => !parts.includes(u));
      const allowedSlots = Math.max(0, limit - parts.length);
      const finalAdd = unique.slice(0, allowedSlots);
      const next = Array.from(new Set([...parts, ...finalAdd]));

      tx.set(chatRef, {
        participants: next,
        membersCount: next.length,
        type: "group",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessage: finalAdd.length ? `${finalAdd.length} miembro(s) añadido(s)` : (c.lastMessage || ""),
        lastSenderId: finalAdd.length ? me : (c.lastSenderId || me),
      }, { merge: true });

      if (finalAdd.length) {
        const names = await fetchUsernames(finalAdd);
        const msgRef = chatRef.collection("messages").doc();
        tx.set(msgRef, {
          id: msgRef.id,
          chatId,
          senderId: me,
          text: `añadió a ${names.join(", ")}`,
          system: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    return { ok: true, chatId };
  });


export const grantAdmin = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string; userId: string }, context) => {
    const auth = context.auth;
    if (!auth || !auth.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const me = auth.uid;
    const chatId = String(data?.chatId || "");
    const userId = String(data?.userId || "");
    if (!chatId || !userId) throw new functions.https.HttpsError("invalid-argument", "chatId y userId requeridos");

    const chatRef = db.collection("chats").doc(chatId);
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
    const c = snap.data() || {};
    const parts: string[] = (c.participants || []).filter(Boolean);
    if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");
    if (!parts.includes(userId)) throw new functions.https.HttpsError("failed-precondition", "Usuario no es miembro");

    const ownerId: string = String(c.ownerId || c.createdBy || "");
    if (me !== ownerId) throw new functions.https.HttpsError("permission-denied", "Solo el owner puede promover admins");

    const admins: string[] = Array.isArray(c.admins) ? c.admins.filter(Boolean) : [];
    if (admins.includes(userId)) return { ok: true, chatId }; // idempotente

    const newAdmins = Array.from(new Set([...admins, userId]));
    await chatRef.set({
      admins: newAdmins,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    const promotedName = await fetchUsername(userId);
    await chatRef.collection("messages").add({
      text: `promovió a ${promotedName} a admin`,
      system: true,
      senderId: me,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, chatId };
  });

export const revokeAdmin = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { chatId: string; userId: string }, context) => {
    const auth = context.auth;
    if (!auth || !auth.uid) throw new functions.https.HttpsError("unauthenticated", "Auth requerida");
    const me = auth.uid;
    const chatId = String(data?.chatId || "");
    const userId = String(data?.userId || "");
    if (!chatId || !userId) throw new functions.https.HttpsError("invalid-argument", "chatId y userId requeridos");

    const chatRef = db.collection("chats").doc(chatId);
    const snap = await chatRef.get();
    if (!snap.exists) throw new functions.https.HttpsError("not-found", "Chat no existe");
    const c = snap.data() || {};
    const parts: string[] = (c.participants || []).filter(Boolean);
    if (!parts.includes(me)) throw new functions.https.HttpsError("permission-denied", "No miembro");

    const ownerId: string = String(c.ownerId || c.createdBy || "");
    if (me !== ownerId) throw new functions.https.HttpsError("permission-denied", "Solo el owner puede quitar admins");

    const admins: string[] = Array.isArray(c.admins) ? c.admins.filter(Boolean) : [];
    if (!admins.includes(userId)) return { ok: true, chatId }; // idempotente

    const newAdmins = admins.filter((a) => a !== userId);
    await chatRef.set({
      admins: newAdmins,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    const demotedName = await fetchUsername(userId);
    await chatRef.collection("messages").add({
      text: `quitó admin a ${demotedName}`,
      system: true,
      senderId: me,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ok: true, chatId };
  });

export const backfillChatRoles = functions
  .region(CONFIG.REGION)
  .https.onCall(async (data: { dryRun?: boolean; batchSize?: number; startAfterId?: string }, context) => {
    // Seguridad: sólo soporte/admin puede ejecutar
    const allowed = await isSupportAdmin(context.auth);
    if (!allowed) {
      throw new functions.https.HttpsError("permission-denied", "Solo admin/support.");
    }

    const dryRun = data?.dryRun !== false; // por defecto SÍ dryRun
    const batchSize = Math.max(1, Math.min(500, Number(data?.batchSize ?? 300)));
    const startAfterId = (data?.startAfterId || "").trim();

    let q = db.collection("chats")
      .where("type", "==", "group")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(batchSize);

    if (startAfterId) {
      const afterRef = db.collection("chats").doc(startAfterId);
      const afterSnap = await afterRef.get();
      if (afterSnap.exists) {
        q = q.startAfter(afterSnap.id);
      }
    }

    const snap = await q.get();

    let scanned = 0;
    let updated = 0;
    let skippedNoParticipants = 0;
    const updatedIds: string[] = [];

    for (const doc of snap.docs) {
      scanned++;
      const d = doc.data() || {};
      const participants: string[] = Array.isArray(d.participants) ? d.participants.filter(Boolean) : [];

      if (!participants.length) {
        skippedNoParticipants++;
        continue;
      }

      const hasOwner = typeof d.ownerId === "string" && d.ownerId.length > 0;
      const hasAdmins = Array.isArray(d.admins);

      if (hasOwner && hasAdmins) {
        // Nada que hacer
        continue;
      }

      // Cálculo de owner/admins sin pisar lo que ya esté
      let ownerId: string = hasOwner ? String(d.ownerId) : String(d.createdBy || participants[0] || "");
      if (!participants.includes(ownerId) && participants.length > 0) {
        ownerId = participants[0]; // fallback: primer miembro
      }

      let admins: string[] = hasAdmins ? d.admins.filter((x: any) => typeof x === "string" && x) : [];
      // Limpieza: sin duplicados, deben ser miembros
      const uniqSet = new Set<string>();
      admins = admins.filter((a: string) => {
        if (!participants.includes(a)) return false;
        if (a === ownerId) return false; // el owner no necesita estar en admins
        if (uniqSet.has(a)) return false;
        uniqSet.add(a);
        return true;
      });

      const patch: Record<string, any> = {};
      if (!hasOwner) patch.ownerId = ownerId;
      if (!hasAdmins) patch.admins = admins;

      if (!dryRun) {
        await doc.ref.set({
          ...patch,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      updated++;
      updatedIds.push(doc.id);
    }

    // Paginación: sugerencia del nextStartAfterId
    const lastDoc = snap.docs[snap.docs.length - 1];
    const nextStartAfterId = lastDoc ? lastDoc.id : null;

    return {
      ok: true,
      dryRun,
      scanned,
      updated,
      skippedNoParticipants,
      updatedIds,
      nextStartAfterId,
      hint: "Vuelve a llamar pasando startAfterId para continuar, o dryRun:false para aplicar.",
    };
  });
