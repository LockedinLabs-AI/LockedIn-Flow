import AppKit
import ApplicationServices
import VoiceCore

public enum InsertionError: Error, LocalizedError, Equatable {
    case noTargetApplication
    case accessibilityNotTrusted
    case secureField
    case targetSecurityUnverifiable
    /// Cmd+V was already dispatched when the target's security state became
    /// unreadable or secure. Delivery is unknowable, so sensitive content is
    /// discarded while the user is told to inspect the original destination.
    case sensitiveInsertionUnverified
    case focusChanged
    /// The application never changed, but an exact control captured for a
    /// protected or explicit delivery is no longer the focused one. Browsers and Electron
    /// editors rebuild their focused control routinely, so this is a distinct,
    /// recoverable condition rather than a target-application change.
    case targetFieldChanged
    case insertionRejected
    case insertionUnverified
    /// The AX setter may have delivered text, but verification was inconclusive
    /// and the clipboard changed during that window. Keep the newer clipboard
    /// and retain the transcript only in History/Recovery for inspection.
    case accessibilityInsertionUnverifiedPreservingClipboard
    /// An owned staging or automatic-write rollback could not prove that the
    /// prior pasteboard item graph was restored. Never overwrite or retry from
    /// this state; the user must inspect the clipboard.
    case clipboardRestorationUnverified
    /// A paste command was already dispatched, delivery stayed unknown, and
    /// the prior clipboard contents could not be proven restored. Never send a
    /// second paste; the user must inspect both the target and clipboard.
    case insertionAndClipboardRestorationUnverified
    /// Sensitive target evidence stopped the paste command, but the temporary
    /// staged transcript could not be proven removed from the clipboard.
    case sensitiveClipboardRestorationUnverifiedBeforeInsertion
    /// A paste command was already dispatched when sensitive target evidence
    /// appeared, and the temporary clipboard restoration also became unknown.
    case sensitiveClipboardRestorationUnverifiedAfterInsertionBegan
    /// Another process replaced the staged clipboard contents before Cmd+V.
    /// No event was sent; the newer clipboard must remain untouched while the
    /// transcript stays recoverable inside LockedIn Flow.
    case clipboardChangedBeforeInsertion
    /// Cmd+V was dispatched, then staged clipboard ownership was lost before
    /// delivery could be verified. Never repaste; preserve the newer clipboard
    /// and require the user to inspect the original target.
    case clipboardChangedAfterInsertionBegan

    public var errorDescription: String? {
        switch self {
        case .noTargetApplication: return "No target application found for insertion."
        case .accessibilityNotTrusted: return "Accessibility permission is required to insert text."
        case .secureField: return "Dictation into password fields is blocked for your safety."
        case .targetSecurityUnverifiable:
            return "The target field's security could not be verified."
        case .sensitiveInsertionUnverified:
            return "The sensitive insertion could not be verified after delivery began."
        case .focusChanged: return "Focus moved to another application before insertion."
        case .targetFieldChanged: return "The focused text field changed before insertion."
        case .insertionRejected: return "The target field rejected the inserted text."
        case .insertionUnverified: return "The insertion could not be verified."
        case .accessibilityInsertionUnverifiedPreservingClipboard:
            return "The insertion and clipboard state changed before delivery could be verified."
        case .clipboardRestorationUnverified:
            return "The previous clipboard contents could not be restored reliably."
        case .insertionAndClipboardRestorationUnverified:
            return "The insertion and previous clipboard restoration could not be verified."
        case .sensitiveClipboardRestorationUnverifiedBeforeInsertion:
            return "Sensitive clipboard staging could not be cleared reliably before insertion."
        case .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan:
            return "Sensitive insertion and clipboard restoration could not be verified."
        case .clipboardChangedBeforeInsertion:
            return "The clipboard changed before insertion."
        case .clipboardChangedAfterInsertionBegan:
            return "The clipboard changed before insertion could be verified."
        }
    }

    /// Secure-target failures are categorically different from delivery
    /// failures. A transcript that may contain a credential must not enter the
    /// clipboard or any recovery/history store. All other insertion failures
    /// retain the product's normal recoverability guarantee.
    public var requiresSensitiveContentDiscard: Bool {
        self == .secureField
            || self == .targetSecurityUnverifiable
            || self == .sensitiveInsertionUnverified
            || self == .sensitiveClipboardRestorationUnverifiedBeforeInsertion
            || self == .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan
    }

    /// Recovery may retain the transcript, but it must not replace a newer
    /// clipboard value written by the user or another application.
    public var requiresExternalClipboardPreservation: Bool {
        self == .clipboardChangedBeforeInsertion
            || self == .clipboardChangedAfterInsertionBegan
            || self == .accessibilityInsertionUnverifiedPreservingClipboard
            || self == .clipboardRestorationUnverified
            || self == .insertionAndClipboardRestorationUnverified
            || self == .sensitiveClipboardRestorationUnverifiedBeforeInsertion
            || self == .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan
    }

    /// Cancellation normally suppresses every late controller effect, but
    /// these outcomes prove either that delivery may already have begun or
    /// that temporary clipboard staging could not be removed. The controller
    /// may surface only a terminal inspection notice for them; it must not
    /// recover, retry, or copy the transcript.
    public var requiresCancellationSafetyNotice: Bool {
        switch self {
        case .clipboardRestorationUnverified,
            .sensitiveClipboardRestorationUnverifiedBeforeInsertion,
            .insertionUnverified,
            .accessibilityInsertionUnverifiedPreservingClipboard,
            .clipboardChangedAfterInsertionBegan,
            .insertionAndClipboardRestorationUnverified,
            .sensitiveInsertionUnverified,
            .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan:
            return true
        default:
            return false
        }
    }

    /// A re-insertion must not offer another paste while the user has not yet
    /// inspected an outcome that may already have delivered text or left
    /// temporary clipboard staging unresolved. A separate acknowledgement is
    /// required before a later, deliberate re-insertion can begin.
    public var requiresReinsertInspection: Bool {
        requiresCancellationSafetyNotice
    }

    /// Truthful recovery copy for clipboard ownership/restoration failures.
    /// Recovery stays in LockedIn Flow and never triggers a fallback clipboard
    /// write from these states.
    public var clipboardPreservationUserMessage: String? {
        switch self {
        case .clipboardChangedBeforeInsertion:
            return "The clipboard changed, so no paste command was sent. "
                + "Your newer clipboard was preserved; the transcript remains in LockedIn Flow for retry."
        case .clipboardChangedAfterInsertionBegan:
            return "Check the original field before continuing. "
                + "The paste command was sent, but the clipboard changed before delivery could be verified. "
                + "Your newer clipboard was preserved and the transcript remains in LockedIn Flow."
        case .accessibilityInsertionUnverifiedPreservingClipboard:
            return "Check the original field before continuing. "
                + "LockedIn Flow could not verify the direct insertion. "
                + "Your newer clipboard was preserved and the transcript remains in LockedIn Flow."
        case .clipboardRestorationUnverified:
            return
                "No paste command was sent. Check the clipboard before retrying because LockedIn Flow could not verify restoration of its prior contents; the transcript remains in LockedIn Flow."
        case .insertionAndClipboardRestorationUnverified:
            return
                "Inspect the original field and clipboard before continuing. A paste command was sent, but neither delivery nor restoration of the prior clipboard could be verified. No second paste was sent; the transcript remains in LockedIn Flow."
        case .sensitiveClipboardRestorationUnverifiedBeforeInsertion:
            return
                "Clear or inspect the clipboard before continuing. No paste command was sent, but LockedIn Flow could not verify removal of the sensitive staged transcript. Nothing was saved in LockedIn Flow."
        case .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan:
            return
                "Inspect the original field and clear or inspect the clipboard before continuing. A paste command was sent, and neither delivery nor removal of the sensitive staged transcript could be verified. Nothing was saved in LockedIn Flow."
        default:
            return nil
        }
    }
}

public struct InsertionResult: Sendable, Equatable {
    public enum Method: String, Sendable {
        case accessibilitySelectedText
        case pasteboard

    }

    /// Describes who still owns the clipboard after insertion. The controller
    /// may honor auto-copy only when the AX path proves the clipboard has not
    /// changed since delivery began; paste transport manages its own staging.
    public enum ClipboardDisposition: Sendable, Equatable {
        case pasteTransportManaged
        /// Delivery was confirmed, but restoration of the prior clipboard was
        /// not. The insertion remains successful and must never be retried.
        case pasteTransportRestorationUnverified
        case copyIfUnchanged(expectedChangeCount: Int)
        case newerExternalContentPreserved
    }

    public var method: Method
    public var charactersInserted: Int
    public var clipboardDisposition: ClipboardDisposition

    public init(
        method: Method,
        charactersInserted: Int,
        clipboardDisposition: ClipboardDisposition = .pasteTransportManaged
    ) {
        self.method = method
        self.charactersInserted = charactersInserted
        self.clipboardDisposition = clipboardDisposition
    }
}

/// Retained identity for an exact non-secure control selected by a delivery
/// workflow. The Accessibility handle is intentionally private: callers can
/// keep the opaque token, but cannot use it as a
/// general-purpose Accessibility capability. The single content-reading
/// operation is `TextInserter.editWatchValue(of:)`, which exists only for the
/// user-enabled learn-from-edits feature and refuses secure fields.
public struct CapturedInsertionTarget: Sendable {
    public let focusLock: InsertionFocusLock
    fileprivate let control: CapturedAXControl
    fileprivate let contract: CapturedTargetContract

    /// True only when post-insertion observation can remain bound to the exact
    /// control used for delivery. Renderer-backed logical targets may remount,
    /// so edit learning is disabled for those deliveries.
    public var supportsExactPostDeliveryObservation: Bool {
        if case .exactControl = contract { return true }
        return false
    }

    fileprivate init(
        focusLock: InsertionFocusLock,
        element: AXUIElement,
        contract: CapturedTargetContract = .exactControl
    ) {
        self.focusLock = focusLock
        self.control = CapturedAXControl(element)
        self.contract = contract
    }
}

/// Result of one ordinary delivery transaction. The opaque target is returned
/// only so the application can start its optional post-insertion edit watch;
/// callers must not retain it for a later insertion.
public struct OrdinaryInsertionDelivery: Sendable {
    public let result: InsertionResult
    public let target: CapturedInsertionTarget

    fileprivate init(
        result: InsertionResult,
        target: CapturedInsertionTarget
    ) {
        self.result = result
        self.target = target
    }
}

/// A short-lived safety contract used inside one delivery transaction.
/// Protected workflows retain one exact Accessibility control. Codex and
/// Claude ordinary delivery instead retains a logical application target so a
/// renderer may replace the AX proxy before the single write boundary.
fileprivate enum CapturedTargetContract: Sendable {
    case exactControl
    case dynamicApplication(CapturedDynamicTargetIdentity)
}

/// Content-free identity for one logical dynamic editor. The owning window is
/// retained as an AX identity while the semantic signature uses only roles,
/// subroles, and identifiers—never titles, values, descriptions, or text.
/// On the narrow Codex/Claude ordinary-dictation allowlist, a newly focused AX
/// proxy with this same window and signature is intentionally the same logical
/// destination: Accessibility exposes no durable leaf-continuity identifier.
/// A different window or semantic signature is always rejected. Protected and
/// non-allowlisted workflows keep exact-control identity instead.
fileprivate final class CapturedDynamicTargetIdentity: @unchecked Sendable {
    let window: AXUIElement
    let semanticSignature: DynamicControlSemanticSignature

    init(window: AXUIElement, semanticSignature: DynamicControlSemanticSignature) {
        self.window = window
        self.semanticSignature = semanticSignature
    }
}

/// `AXUIElement` is an immutable Core Foundation proxy identity, not mutable
/// field storage. Exact-control workflows reacquire focus and compare this
/// identity before use. A dynamic ordinary target retains it only as an
/// activation/edit-watch hint; delivery follows fresh app-level focus evidence
/// and never requires this proxy to remain `CFEqual`. The wrapper exposes
/// neither the handle nor any general content-reading operation.
fileprivate final class CapturedAXControl: @unchecked Sendable {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }
}

/// Result of observing the caret around a paste operation. A paste is only
/// reported as successful when Accessibility confirms that the caret advanced
/// by the inserted UTF-16 length. No field contents are read to do this.
enum PasteVerification: Equatable {
    case confirmed
    /// The exact caret advance confirmed delivery, but restoring the clipboard
    /// afterward failed. This is still a successful, at-most-once insertion.
    case confirmedWithClipboardRestorationUnverified
    case unavailable
    case rejected

    static func evaluate(
        before: CFRange?,
        after: CFRange?,
        insertedUTF16Count: Int
    ) -> PasteVerification {
        guard let before, let after,
            before.location >= 0,
            before.length >= 0,
            insertedUTF16Count > 0
        else {
            return .unavailable
        }
        let (expectedLocation, overflowed) = before.location.addingReportingOverflow(
            insertedUTF16Count
        )
        guard !overflowed else { return .unavailable }
        return after.location == expectedLocation && after.length == 0
            ? .confirmed
            : .rejected
    }
}

/// Incremental paste receipt used while an editor remounts its Accessibility
/// control. A transient missing observation is not a failure by itself, but no
/// sequence succeeds until one freshly observed range proves the exact caret
/// advance. Persistent absence therefore remains `.unavailable`.
struct PasteVerificationAccumulator {
    private(set) var result: PasteVerification = .unavailable

    mutating func observe(
        before: CFRange,
        after: CFRange?,
        insertedUTF16Count: Int
    ) -> Bool {
        guard let after else { return false }
        result = PasteVerification.evaluate(
            before: before,
            after: after,
            insertedUTF16Count: insertedUTF16Count
        )
        return result == .confirmed
    }
}

/// A dynamic editor destination paired with the caret or replacement selection
/// observed before its final policy revalidation. Keeping these together prevents the
/// transport from performing an unguarded range read after the resolver has
/// proved application identity, focus, generation, and non-secure status.
struct DynamicPasteTargetEvidence {
    let element: AXUIElement
    let selectedTextRange: CFRange
}

enum SecureFieldClassification: Equatable {
    case secure
    case nonsecure
    case unknown
}

struct DynamicControlSemanticSignature: Equatable {
    struct Node: Equatable {
        let role: String
        let subrole: String?
        let identifier: String?
    }

    let leaf: Node
    let ancestors: [Node]

    static func normalizedComposer(
        leafSubrole: String?,
        leafIdentifier: String?,
        ancestors: [Node]
    ) -> DynamicControlSemanticSignature {
        DynamicControlSemanticSignature(
            leaf: Node(
                role: "AXDynamicComposerText",
                subrole: leafSubrole,
                identifier: leafIdentifier
            ),
            ancestors: ancestors.filter { node in
                node.identifier != nil
                    || node.role.hasPrefix("AXLandmark")
                    || node.subrole?.hasPrefix("AXLandmark") == true
                    || node.role == "AXWebArea"
                    || node.role == "AXScrollArea"
            }
        )
    }
}

struct DynamicControlDescriptor {
    let window: AXUIElement
    let semanticSignature: DynamicControlSemanticSignature
}

struct DynamicControlSnapshot {
    let element: AXUIElement
    let descriptor: DynamicControlDescriptor
}

/// Content-free diagnostic for the last incomplete observation made while
/// resolving a dynamic editor at an explicit target boundary.
fileprivate enum DynamicCaptureReadinessStage: String {
    case focusedElement = "focused-element"
    case textCapability = "text-capability"
    case semanticDescriptor = "semantic-descriptor"
    case security = "security"
    case stability = "stability"
}

enum DynamicEditableLeafEligibility: Equatable {
    case eligible
    case ineligible
    case unknown
}

enum DynamicSemanticStringObservation: Equatable {
    case value(String?)
    case unknown
}

func dynamicSemanticStringObservation(
    status: AXError,
    value: CFTypeRef?
) -> DynamicSemanticStringObservation {
    switch status {
    case .success:
        guard let string = value as? String else { return .unknown }
        return .value(string.isEmpty ? nil : string)
    case .attributeUnsupported, .noValue:
        return .value(nil)
    default:
        return .unknown
    }
}

/// Pure tri-state for the AX facts that distinguish an editable composer leaf
/// from the many range-advertising containers in a web hierarchy. Missing or
/// failed facts on a text-like role stay unknown so a temporarily unreadable
/// control cannot be mistaken for a proven composer.
func dynamicEditableLeafEligibility(
    roleReadSucceeded: Bool,
    role: String?,
    selectedTextRangeSettable: Bool?,
    characterCount: Int?
) -> DynamicEditableLeafEligibility {
    guard roleReadSucceeded, let role, !role.isEmpty else { return .unknown }
    guard role == "AXTextArea" || role == "AXGroup" else {
        return .ineligible
    }
    guard let selectedTextRangeSettable else { return .unknown }
    guard selectedTextRangeSettable else { return .ineligible }
    guard let characterCount, characterCount >= 0 else { return .unknown }
    if role == "AXGroup", characterCount != 0 { return .ineligible }
    return .eligible
}

/// Evidence collected after an Accessibility selected-text write. macOS can
/// return `.success` from `AXUIElementSetAttributeValue` even when a browser
/// ignores the edit, so the API result alone is never a delivery receipt.
enum AXInsertionVerification: Equatable {
    /// The collapsed caret and character count match the exact insertion.
    case confirmed
    /// The direct write was refused before calling the AX setter. General mode
    /// may proceed to its independently verified paste transport.
    case notAttempted
    /// The AX setter was called but exact delivery could not be proved. The
    /// target may already contain the text, so no automatic retry is safe.
    case outcomeUnknown

    static func canAttempt(
        beforeRange: CFRange?,
        beforeCharacterCount: Int?,
        insertedUTF16Count: Int
    ) -> Bool {
        guard let beforeRange,
            let beforeCharacterCount,
            beforeRange.location >= 0,
            beforeRange.length == 0,
            beforeCharacterCount >= beforeRange.location,
            insertedUTF16Count > 0
        else {
            return false
        }
        return true
    }

    static func evaluate(
        beforeRange: CFRange?,
        afterRange: CFRange?,
        beforeCharacterCount: Int?,
        afterCharacterCount: Int?,
        insertedUTF16Count: Int
    ) -> AXInsertionVerification {
        guard
            canAttempt(
                beforeRange: beforeRange,
                beforeCharacterCount: beforeCharacterCount,
                insertedUTF16Count: insertedUTF16Count
            ),
            let beforeRange,
            let afterRange,
            let beforeCharacterCount,
            let afterCharacterCount,
            beforeRange.location >= 0,
            afterRange.location >= 0,
            afterRange.length >= 0,
            afterCharacterCount >= 0
        else {
            return .outcomeUnknown
        }

        let (expectedCaretLocation, caretOverflowed) = beforeRange.location
            .addingReportingOverflow(insertedUTF16Count)
        let (expectedCount, countOverflowed) =
            beforeCharacterCount
            .addingReportingOverflow(insertedUTF16Count)
        guard !caretOverflowed, !countOverflowed else {
            return .outcomeUnknown
        }
        let caretConfirmed =
            afterRange.location == expectedCaretLocation
            && afterRange.length == 0
        return caretConfirmed && afterCharacterCount == expectedCount
            ? .confirmed
            : .outcomeUnknown
    }
}

/// A lossless, item-aware snapshot of pasteboard contents. A pasteboard can
/// contain several items that advertise the same type, and each item can carry
/// several representations. Flattening those representations into calls to
/// `NSPasteboard.setData` collapses them into one item and changes what the next
/// application receives when it pastes.
struct PasteboardContentsSnapshot: Equatable {
    struct Item: Equatable {
        struct Representation: Equatable {
            let type: NSPasteboard.PasteboardType
            let data: Data
        }

        let representations: [Representation]

        init(_ item: NSPasteboardItem) {
            representations = item.types.compactMap { type in
                item.data(forType: type).map { Representation(type: type, data: $0) }
            }
        }

        func makePasteboardItem() -> NSPasteboardItem {
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: representation.type)
            }
            return item
        }
    }

    let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map(Item.init) ?? []
    }

    init(items: [NSPasteboardItem]) {
        self.items = items.map(Item.init)
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        let restoredChangeCount = pasteboard.prepareForNewContents(with: .currentHostOnly)
        if !items.isEmpty,
            !pasteboard.writeObjects(items.map { $0.makePasteboardItem() })
        {
            return false
        }
        let readback = PasteboardContentsSnapshot(pasteboard: pasteboard)
        return pasteboard.changeCount == restoredChangeCount
            && readback == self
    }
}

/// Truthful result for an automatic clipboard write. Callers must not collapse
/// these states into a Boolean because only one proves the requested transcript
/// is on the clipboard, and only one proves a newer generation was preserved.
public enum PasteboardWriteOutcome: Sendable, Equatable {
    case written
    case newerContentPreserved
    case originalContentsRestored
    case clipboardUnchanged
    case outcomeUnverified

    public var didWrite: Bool { self == .written }
}

/// Content-free generation captured across an async AX/meeting/recovery wait.
/// Item representations are read only if an automatic write is actually
/// attempted at an unchanged generation. Protected callers may omit this token.
public struct PasteboardGenerationBaseline: Sendable, Equatable {
    private let changeCount: Int

    public init(pasteboard: NSPasteboard = .general) {
        changeCount = pasteboard.changeCount
    }

    /// Writes only when the generation has not advanced. Paste staging and
    /// restoration deliberately advance it, so generic recovery then stays
    /// in History/Recovery rather than speculatively replacing the clipboard.
    @discardableResult
    public func writeStringIfUnchanged(
        _ text: String,
        to pasteboard: NSPasteboard = .general
    ) -> PasteboardWriteOutcome {
        writePasteboardString(
            text,
            to: pasteboard,
            ifChangeCountMatches: changeCount
        )
    }
}

typealias PasteboardItemWriter = (NSPasteboard, NSPasteboardItem) -> Bool
typealias PasteboardSnapshotRestorer = (
    PasteboardContentsSnapshot,
    NSPasteboard
) -> Bool

/// AX success carries a precise change count because no internal pasteboard
/// staging should have occurred. Recheck it at the literal auto-copy boundary.
@discardableResult
public func writePasteboardString(
    _ text: String,
    to pasteboard: NSPasteboard = .general,
    ifChangeCountMatches expectedChangeCount: Int
) -> PasteboardWriteOutcome {
    writePasteboardString(
        text,
        to: pasteboard,
        ifChangeCountMatches: expectedChangeCount,
        writeStagedItem: { pasteboard, item in
            pasteboard.writeObjects([item])
        },
        restoreSnapshot: { snapshot, pasteboard in
            snapshot.restore(to: pasteboard)
        }
    )
}

@discardableResult
func writePasteboardString(
    _ text: String,
    to pasteboard: NSPasteboard,
    ifChangeCountMatches expectedChangeCount: Int,
    writeStagedItem: PasteboardItemWriter,
    restoreSnapshot: PasteboardSnapshotRestorer = { snapshot, pasteboard in
        snapshot.restore(to: pasteboard)
    }
) -> PasteboardWriteOutcome {
    guard pasteboard.changeCount == expectedChangeCount else {
        return .newerContentPreserved
    }
    guard let intended = try? intendedPasteboardString(text) else {
        return .clipboardUnchanged
    }
    let observedContents = PasteboardContentsSnapshot(pasteboard: pasteboard)
    guard pasteboard.changeCount == expectedChangeCount else {
        return .newerContentPreserved
    }
    let clearedChangeCount = pasteboard.prepareForNewContents(with: .currentHostOnly)
    guard clearedChangeCount == (expectedChangeCount &+ 1) else {
        return .outcomeUnverified
    }
    guard writeStagedItem(pasteboard, intended.item) else {
        if pasteboard.changeCount == clearedChangeCount {
            guard restoreSnapshot(observedContents, pasteboard) else {
                return .outcomeUnverified
            }
            let restoredChangeCount = pasteboard.changeCount
            let restored = PasteboardContentsSnapshot(pasteboard: pasteboard)
            guard pasteboard.changeCount == restoredChangeCount,
                restored == observedContents
            else {
                return .outcomeUnverified
            }
            return .originalContentsRestored
        }
        return .outcomeUnverified
    }
    let writtenChangeCount = pasteboard.changeCount
    let readback = PasteboardContentsSnapshot(pasteboard: pasteboard)
    guard writtenChangeCount == clearedChangeCount,
        pasteboard.changeCount == writtenChangeCount
    else {
        return .outcomeUnverified
    }
    guard readback == intended.snapshot else {
        return .outcomeUnverified
    }
    return .written
}

typealias StagedPasteboardOwnershipValidator = () throws -> Void
typealias MainActorStagedPasteboardOwnershipValidator = @MainActor () throws -> Void
typealias StagedPasteboardWriter = (NSPasteboard, NSPasteboardItem) -> Bool

private func intendedPasteboardString(
    _ text: String
) throws -> (item: NSPasteboardItem, snapshot: PasteboardContentsSnapshot) {
    let item = NSPasteboardItem()
    guard item.setString(text, forType: .string) else {
        throw InsertionError.insertionRejected
    }
    return (item, PasteboardContentsSnapshot(items: [item]))
}

func clipboardErrorAfterPasteEvent(_ error: Error) -> InsertionError {
    if let insertionError = error as? InsertionError,
        insertionError == .sensitiveClipboardRestorationUnverifiedBeforeInsertion
            || insertionError
                == .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan
    {
        return .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan
    }
    if (error as? InsertionError)?.requiresSensitiveContentDiscard == true {
        return .sensitiveInsertionUnverified
    }
    switch error as? InsertionError {
    case .clipboardChangedBeforeInsertion,
        .clipboardChangedAfterInsertionBegan:
        return .clipboardChangedAfterInsertionBegan
    case .insertionAndClipboardRestorationUnverified:
        return .insertionAndClipboardRestorationUnverified
    default:
        return .insertionUnverified
    }
}

private func clipboardRestorationError(combining originalError: Error) -> InsertionError {
    guard let insertionError = originalError as? InsertionError else {
        return .clipboardRestorationUnverified
    }
    if insertionError.requiresSensitiveContentDiscard {
        if insertionError == .sensitiveInsertionUnverified
            || insertionError
                == .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan
        {
            return .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan
        }
        return .sensitiveClipboardRestorationUnverifiedBeforeInsertion
    }
    switch insertionError {
    case .insertionUnverified, .clipboardChangedAfterInsertionBegan,
        .insertionAndClipboardRestorationUnverified:
        return .insertionAndClipboardRestorationUnverified
    default:
        return .clipboardRestorationUnverified
    }
}

private func prioritizedPasteTransportError(
    _ error: Error,
    didPostEvent: Bool,
    validateStagedOwnership: StagedPasteboardOwnershipValidator
) -> Error {
    // A positively observed secure/unknown-sensitive state always wins so the
    // controller scrubs the transcript even if the user also copied. Once an
    // event was sent, retain the sensitive unknown-outcome wording.
    if (error as? InsertionError)?.requiresSensitiveContentDiscard == true {
        return didPostEvent ? clipboardErrorAfterPasteEvent(error) : error
    }

    do {
        try validateStagedOwnership()
    } catch {
        return didPostEvent
            ? InsertionError.clipboardChangedAfterInsertionBegan
            : InsertionError.clipboardChangedBeforeInsertion
    }

    return didPostEvent ? clipboardErrorAfterPasteEvent(error) : error
}

/// Shared at-most-once boundary for synchronous exact and compatibility paste.
/// Ownership loss before `postEvent` returns means zero event; loss during the
/// receipt window is an explicitly unknown post-event outcome and never causes
/// a second paste.
func performSynchronousPasteEventTransport<Result>(
    validateStagedOwnership: @escaping StagedPasteboardOwnershipValidator,
    postEvent: (StagedPasteboardOwnershipValidator) throws -> Void,
    receipt: (StagedPasteboardOwnershipValidator) throws -> Result
) throws -> Result {
    var didPostEvent = false
    do {
        try postEvent(validateStagedOwnership)
        didPostEvent = true
        return try receipt(validateStagedOwnership)
    } catch {
        throw prioritizedPasteTransportError(
            error,
            didPostEvent: didPostEvent,
            validateStagedOwnership: validateStagedOwnership
        )
    }
}

/// Keeps temporary dictation text on the pasteboard for the complete global
/// paste/verification window, then restores the exact prior item structure on
/// both success and thrown late-boundary validation failures.
func withStagedPasteboardString(
    _ text: String,
    on pasteboard: NSPasteboard,
    restoreClipboard: Bool,
    validateBeforeStaging: () throws -> Void,
    writeStagedItem: StagedPasteboardWriter = { pasteboard, item in
        pasteboard.writeObjects([item])
    },
    restoreSavedSnapshot: PasteboardSnapshotRestorer = { snapshot, pasteboard in
        snapshot.restore(to: pasteboard)
    },
    operation: (@escaping StagedPasteboardOwnershipValidator) throws -> PasteVerification
) throws -> PasteVerification {
    // Build the exact one-item payload before observing or mutating the shared
    // pasteboard. Readback is always compared to this intended snapshot; a
    // racing writer can never become the transaction's adopted baseline.
    let intended = try intendedPasteboardString(text)

    // This is the last check before the first pasteboard write. A target that
    // has become secure, changed control, or lost focus must leave the system
    // pasteboard completely untouched.
    try validateBeforeStaging()

    // Snapshot only after target validation. A user or another application may
    // copy while Accessibility is being queried; that newer clipboard is the
    // value this transaction must restore, not the stale pre-validation one.
    let savedChangeCount = pasteboard.changeCount
    let saved = PasteboardContentsSnapshot(pasteboard: pasteboard)
    guard pasteboard.changeCount == savedChangeCount else {
        throw InsertionError.clipboardChangedBeforeInsertion
    }
    // Device-local preparation claims the next generation; `writeObjects`
    // fills that generation without advancing it. These checks detect races
    // and validate exact readback, but macOS exposes no cross-process CAS.
    let clearedChangeCount = pasteboard.prepareForNewContents(with: .currentHostOnly)
    guard clearedChangeCount == (savedChangeCount &+ 1) else {
        throw InsertionError.clipboardRestorationUnverified
    }
    guard writeStagedItem(pasteboard, intended.item) else {
        if pasteboard.changeCount == clearedChangeCount {
            guard restoreSavedSnapshot(saved, pasteboard) else {
                throw InsertionError.clipboardRestorationUnverified
            }
            throw InsertionError.insertionRejected
        }
        throw InsertionError.clipboardRestorationUnverified
    }
    let stagedChangeCount = pasteboard.changeCount
    let stagedReadback = PasteboardContentsSnapshot(pasteboard: pasteboard)
    guard stagedChangeCount == clearedChangeCount,
        pasteboard.changeCount == stagedChangeCount,
        stagedReadback == intended.snapshot
    else {
        // Once our clear/write sequence has begun, a divergent generation or
        // readback does not prove which item graph won the race. Fail without
        // an event and report an unverified clipboard outcome.
        throw InsertionError.clipboardRestorationUnverified
    }

    func validateStagedOwnership() throws {
        guard pasteboard.changeCount == stagedChangeCount else {
            throw InsertionError.clipboardChangedBeforeInsertion
        }
        let current = PasteboardContentsSnapshot(pasteboard: pasteboard)
        guard pasteboard.changeCount == stagedChangeCount,
            current == intended.snapshot
        else {
            throw InsertionError.clipboardChangedBeforeInsertion
        }
    }

    func restoreIfStillOwned() throws {
        guard pasteboard.changeCount == stagedChangeCount else { return }
        guard restoreSavedSnapshot(saved, pasteboard) else {
            throw InsertionError.clipboardRestorationUnverified
        }
    }

    let result: PasteVerification
    do {
        result = try operation(validateStagedOwnership)
    } catch let originalError {
        // Even auto-copy is success-only. Never leave a rejected transcript on
        // the clipboard after a late focus, identity, control, or secure check.
        do {
            try restoreIfStillOwned()
        } catch {
            throw clipboardRestorationError(combining: originalError)
        }
        throw originalError
    }

    // Auto-copy retains the staged transcript only after confirmed delivery.
    // A value-based unavailable/rejected receipt is still a failed operation
    // and must restore the prior clipboard just like a thrown policy error.
    let shouldRestore =
        restoreClipboard
        || result == .unavailable
        || result == .rejected
    if shouldRestore {
        do {
            try restoreIfStillOwned()
        } catch {
            switch result {
            case .confirmed,
                .confirmedWithClipboardRestorationUnverified:
                return .confirmedWithClipboardRestorationUnverified
            case .unavailable, .rejected:
                throw InsertionError.insertionAndClipboardRestorationUnverified
            }
        }
    }
    return result
}

/// Async counterpart used by dynamic renderer-backed editors. Suspending while
/// Accessibility settles keeps activation and cancellation notifications able
/// to advance the capture generation on the main actor. Clipboard restoration
/// retains the same success-only auto-copy contract as the synchronous path.
@MainActor
func withStagedPasteboardString(
    _ text: String,
    on pasteboard: NSPasteboard,
    restoreClipboard: Bool,
    validateBeforeStaging: () throws -> Void,
    writeStagedItem: StagedPasteboardWriter = { pasteboard, item in
        pasteboard.writeObjects([item])
    },
    restoreSavedSnapshot: PasteboardSnapshotRestorer = { snapshot, pasteboard in
        snapshot.restore(to: pasteboard)
    },
    operation: (MainActorStagedPasteboardOwnershipValidator) async throws
        -> PasteVerification
) async throws -> PasteVerification {
    let intended = try intendedPasteboardString(text)
    try validateBeforeStaging()
    let savedChangeCount = pasteboard.changeCount
    let saved = PasteboardContentsSnapshot(pasteboard: pasteboard)
    guard pasteboard.changeCount == savedChangeCount else {
        throw InsertionError.clipboardChangedBeforeInsertion
    }
    // See the synchronous helper: the clear owns the generation and the one
    // `writeObjects` call fills it. This is race detection, not an atomic CAS.
    let clearedChangeCount = pasteboard.prepareForNewContents(with: .currentHostOnly)
    guard clearedChangeCount == (savedChangeCount &+ 1) else {
        throw InsertionError.clipboardRestorationUnverified
    }
    guard writeStagedItem(pasteboard, intended.item) else {
        if pasteboard.changeCount == clearedChangeCount {
            guard restoreSavedSnapshot(saved, pasteboard) else {
                throw InsertionError.clipboardRestorationUnverified
            }
            throw InsertionError.insertionRejected
        }
        throw InsertionError.clipboardRestorationUnverified
    }
    let stagedChangeCount = pasteboard.changeCount
    let stagedReadback = PasteboardContentsSnapshot(pasteboard: pasteboard)
    guard stagedChangeCount == clearedChangeCount,
        pasteboard.changeCount == stagedChangeCount,
        stagedReadback == intended.snapshot
    else {
        throw InsertionError.clipboardRestorationUnverified
    }

    func validateStagedOwnership() throws {
        guard pasteboard.changeCount == stagedChangeCount else {
            throw InsertionError.clipboardChangedBeforeInsertion
        }
        let current = PasteboardContentsSnapshot(pasteboard: pasteboard)
        guard pasteboard.changeCount == stagedChangeCount,
            current == intended.snapshot
        else {
            throw InsertionError.clipboardChangedBeforeInsertion
        }
    }

    func restoreIfStillOwned() throws {
        guard pasteboard.changeCount == stagedChangeCount else { return }
        guard restoreSavedSnapshot(saved, pasteboard) else {
            throw InsertionError.clipboardRestorationUnverified
        }
    }

    let result: PasteVerification
    do {
        result = try await operation(validateStagedOwnership)
    } catch let originalError {
        do {
            try restoreIfStillOwned()
        } catch {
            throw clipboardRestorationError(combining: originalError)
        }
        throw originalError
    }

    let shouldRestore =
        restoreClipboard
        || result == .unavailable
        || result == .rejected
    if shouldRestore {
        do {
            try restoreIfStillOwned()
        } catch {
            switch result {
            case .confirmed,
                .confirmedWithClipboardRestorationUnverified:
                return .confirmedWithClipboardRestorationUnverified
            case .unavailable, .rejected:
                throw InsertionError.insertionAndClipboardRestorationUnverified
            }
        }
    }
    return result
}

final class PasteboardTransactionGate: @unchecked Sendable {
    static let shared = PasteboardTransactionGate()
    private let lock = NSLock()
    private var isHeld = false

    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isHeld else { return false }
        isHeld = true
        return true
    }

    func release() {
        lock.lock()
        isHeld = false
        lock.unlock()
    }
}

func acquirePasteboardTransaction() async throws {
    try Task.checkCancellation()
    while !PasteboardTransactionGate.shared.tryAcquire() {
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

typealias AsyncDynamicPasteboardOperation = (
    MainActorStagedPasteboardOwnershipValidator
) async throws -> PasteVerification

typealias AsyncDynamicPasteboardStage = (
    @escaping () throws -> Void,
    @escaping AsyncDynamicPasteboardOperation
) async throws -> PasteVerification

/// Shared, at-most-once dynamic paste state machine. Production and tests both
/// execute this exact ordering: acquire the process-wide clipboard lease,
/// resolve readiness before staging, synchronously cancel/revalidate at stage
/// and event boundaries, dispatch once, then perform receipt-only polling.
@MainActor
func performDynamicPasteTransport(
    text: String,
    validateBeforeStaging: @escaping () throws -> Void,
    resolveTargetAtGlobalEvent: @escaping () async throws -> DynamicPasteTargetEvidence,
    stage: @escaping AsyncDynamicPasteboardStage,
    postEvent:
        @escaping (
            DynamicPasteTargetEvidence,
            MainActorStagedPasteboardOwnershipValidator
        ) throws -> Void,
    resolveVerificationTargetAfterPaste:
        @escaping () throws -> DynamicPasteTargetEvidence?,
    receiptDelay: @escaping () async throws -> Void,
    acquiresPasteboardLease: Bool = true
) async throws -> PasteVerification {
    if acquiresPasteboardLease {
        try await acquirePasteboardTransaction()
    }

    do {
        let evidence = try await resolveTargetAtGlobalEvent()
        // A successful Accessibility observation can complete without a real
        // suspension. Yield once so queued MainActor cancellation and
        // workspace-activation callbacks become visible before any clipboard
        // write, then let the stage validator re-prove policy synchronously.
        await Task.yield()
        try Task.checkCancellation()
        let result = try await stage(
            {
                try Task.checkCancellation()
                try validateBeforeStaging()
            },
            { validateStagedOwnership in
                var didPostEvent = false
                do {
                    try Task.checkCancellation()
                    try postEvent(evidence, validateStagedOwnership)
                    didPostEvent = true

                    var accumulator = PasteVerificationAccumulator()
                    for _ in 0..<16 {
                        try await receiptDelay()
                        try validateStagedOwnership()
                        let after = try resolveVerificationTargetAfterPaste()?
                            .selectedTextRange
                        try validateStagedOwnership()
                        if accumulator.observe(
                            before: evidence.selectedTextRange,
                            after: after,
                            insertedUTF16Count: text.utf16.count
                        ) {
                            return .confirmed
                        }
                    }
                    return accumulator.result
                } catch {
                    // Event receipt can be retried; event dispatch never can.
                    // If another writer took the clipboard while a target or
                    // delay operation failed, ownership loss is the actionable
                    // outcome unless secure evidence requires scrubbing.
                    throw prioritizedPasteTransportError(
                        error,
                        didPostEvent: didPostEvent,
                        validateStagedOwnership: validateStagedOwnership
                    )
                }
            }
        )
        if acquiresPasteboardLease {
            PasteboardTransactionGate.shared.release()
        }
        return result
    } catch {
        if acquiresPasteboardLease {
            PasteboardTransactionGate.shared.release()
        }
        throw error
    }
}

/// Injectable boundary around macOS Accessibility and pasteboard behavior. It
/// keeps the fail-closed insertion policy independently testable without asking
/// the test runner for Accessibility permission or modifying another app.
protocol TextInsertionEnvironment: AnyObject {
    func isTrusted() -> Bool
    func bundleIdentifier(for pid: pid_t) -> String
    func appName(for pid: pid_t) -> String?
    func frontmostProcessIdentifier() -> pid_t?
    func ownProcessIdentifier() -> pid_t
    @MainActor
    func activateApplication(
        processIdentifier: pid_t,
        targetElement: AXUIElement
    ) async throws -> Bool
    @MainActor
    func requestApplicationActivation(processIdentifier: pid_t) async throws
    func currentActivationGeneration() -> UInt64
    func focusedElement(for pid: pid_t) -> AXUIElement?
    func isElementFocused(_ element: AXUIElement) -> Bool?
    /// Structural text-control evidence that does not require the selected
    /// range value itself to be readable at this instant.
    func supportsSelectedTextRange(_ element: AXUIElement) -> Bool?
    func secureFieldClassification(
        _ element: AXUIElement,
        textCapabilityKnown: Bool
    ) -> SecureFieldClassification
    func dynamicControlDescriptor(
        of element: AXUIElement
    ) -> DynamicControlDescriptor?
    func selectedTextRange(of element: AXUIElement) -> CFRange?
    /// Content-free clipboard generation used to keep AX delivery from
    /// overwriting a user copy made while verification is polling.
    func pasteboardChangeCount() -> Int
    /// `validateBeforeWrite` is idempotent and runs both before and after the
    /// blocking AX evidence reads, immediately before any setter attempt.
    /// `commitDelivery` atomically marks that the next non-suspending operation
    /// is irreversible; a cancelled caller may refuse that commit.
    func insertViaSelectedText(
        _ text: String,
        into element: AXUIElement,
        validateBeforeWrite: () throws -> Void,
        commitDelivery: () throws -> Void
    ) throws -> AXInsertionVerification
    /// Exact-control delivery invokes `validateBeforeGlobalEvent` again after
    /// its blocking range read and before staged ownership and Cmd+V. The
    /// delivery commit runs at the literal event boundary after those proofs.
    func pasteboardInsert(
        _ text: String,
        into element: AXUIElement,
        targetPID: pid_t,
        restoreClipboard: Bool,
        pasteboardLeaseAlreadyHeld: Bool,
        validateBeforeStaging: () throws -> Void,
        validateBeforeGlobalEvent: () throws -> Void,
        commitDelivery: () throws -> Void,
        resolveTargetAtGlobalEvent: (() throws -> DynamicPasteTargetEvidence)?,
        resolveVerificationTargetAfterPaste: (() throws -> DynamicPasteTargetEvidence?)?
    ) throws -> PasteVerification
    @MainActor
    func pasteboardInsertDynamic(
        _ text: String,
        targetPID: pid_t,
        restoreClipboard: Bool,
        validateBeforeStaging: @escaping () throws -> Void,
        commitDelivery: @escaping () throws -> Void,
        resolveTargetAtGlobalEvent:
            @escaping () async throws -> DynamicPasteTargetEvidence,
        validateResolvedTargetAtGlobalEvent:
            @escaping (DynamicPasteTargetEvidence) throws -> Void,
        resolveVerificationTargetAfterPaste:
            @escaping () throws -> DynamicPasteTargetEvidence?
    ) async throws -> PasteVerification
    func postUndoKeystroke(
        validateBeforeGlobalEvent: () throws -> Void
    ) throws
    func fieldValue(of element: AXUIElement) -> String?
}

extension TextInsertionEnvironment {
    /// Environments that predate the opt-in learn-from-edits feature expose
    /// no field contents; the watch simply never starts for them.
    func fieldValue(of element: AXUIElement) -> String? { nil }
}

private final class MacTextInsertionEnvironment: TextInsertionEnvironment {
    private enum DynamicComposerLeafObservation {
        case leaf(DynamicControlSemanticSignature.Node)
        case ineligible
        case unknown
    }

    private enum DynamicAncestorObservation {
        case role(String)
        case reachedWebArea
        case unknown
    }

    private enum SemanticNodeObservation {
        case node(DynamicControlSemanticSignature.Node)
        case unknown
    }

    func isTrusted() -> Bool {
        TextInserter.isTrusted(prompt: false)
    }

    func bundleIdentifier(for pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    }

    func appName(for pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    func frontmostProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func ownProcessIdentifier() -> pid_t {
        ProcessInfo.processInfo.processIdentifier
    }

    @MainActor
    func activateApplication(
        processIdentifier: pid_t,
        targetElement: AXUIElement
    ) async throws -> Bool {
        try Task.checkCancellation()
        guard
            let application = NSRunningApplication(
                processIdentifier: processIdentifier
            )
        else { return false }

        // This call is still the most reliable way to bring an already-running
        // browser/editor forward from an activating AppKit window. Treat its
        // Boolean only as an accepted request; the caller independently polls
        // the actual frontmost PID and revalidates the exact control.
        try Task.checkCancellation()
        if application.activate(options: [.activateAllWindows]) {
            for _ in 0..<8 {
                try await Task.sleep(nanoseconds: 25_000_000)
                try Task.checkCancellation()
                if frontmostProcessIdentifier() == processIdentifier { return true }
            }
        }

        // Browser and Electron processes may ignore a normal activation request
        // from a menu-bar app. Raise only the Accessibility window containing
        // the already captured control, then verify the actual frontmost PID.
        try Task.checkCancellation()
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            targetElement,
            kAXWindowAttribute as CFString,
            &windowValue
        ) == .success,
            let windowValue,
            CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        {
            try Task.checkCancellation()
            _ = AXUIElementPerformAction(
                windowValue as! AXUIElement,  // swiftlint:disable:this force_cast
                kAXRaiseAction as CFString
            )
            try Task.checkCancellation()
            let accessibilityApplication = AXUIElementCreateApplication(processIdentifier)
            _ = AXUIElementSetAttributeValue(
                accessibilityApplication,
                kAXFrontmostAttribute as CFString,
                kCFBooleanTrue
            )
            try await Task.sleep(nanoseconds: 25_000_000)
            try Task.checkCancellation()
            if frontmostProcessIdentifier() == processIdentifier { return true }
        }

        // Do not queue `openApplication`: its completion is not cancellable and
        // could steal focus after the user has already cancelled insertion.
        try Task.checkCancellation()
        return false
    }

    /// Sends bounded activation requests for a frozen pre-capture PID. Unlike
    /// insertion-time focus restoration, this has no captured AX window yet and
    /// must not queue an asynchronous reopen that could steal focus after the
    /// preflight has already timed out.
    @MainActor
    func requestApplicationActivation(processIdentifier: pid_t) async throws {
        try Task.checkCancellation()
        guard
            let application = NSRunningApplication(
                processIdentifier: processIdentifier
            )
        else { return }
        try Task.checkCancellation()
        _ = application.activate(options: [.activateAllWindows])
        try Task.checkCancellation()
        guard frontmostProcessIdentifier() != processIdentifier else { return }
        let accessibilityApplication = AXUIElementCreateApplication(processIdentifier)
        try Task.checkCancellation()
        _ = AXUIElementSetAttributeValue(
            accessibilityApplication,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
    }

    func currentActivationGeneration() -> UInt64 {
        FrontmostTracker.shared.currentActivationGeneration()
    }

    func focusedElement(for pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard status == .success, let focusedValue else { return nil }
        return (focusedValue as! AXUIElement)  // swiftlint:disable:this force_cast
    }

    func isElementFocused(_ element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))  // swiftlint:disable:this force_cast
    }

    func supportsSelectedTextRange(_ element: AXUIElement) -> Bool? {
        var attributeNames: CFArray?
        guard AXUIElementCopyAttributeNames(element, &attributeNames) == .success,
            let names = attributeNames as? [String]
        else {
            return nil
        }
        return names.contains(kAXSelectedTextRangeAttribute)
    }

    func secureFieldClassification(
        _ element: AXUIElement,
        textCapabilityKnown: Bool
    ) -> SecureFieldClassification {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &value
        )
        switch status {
        case .success:
            guard let subrole = value as? String else { return .unknown }
            return subrole == "AXSecureTextField" ? .secure : .nonsecure
        case .noValue, .attributeUnsupported:
            // Many web text controls advertise selected-range capability but no
            // subrole. That explicit combination is non-secure evidence; the
            // same missing subrole on an unproven control remains unknown.
            return textCapabilityKnown ? .nonsecure : .unknown
        default:
            // cannotComplete, invalid UI elements, malformed values, and every
            // other AX failure are never silently treated as non-secure.
            return .unknown
        }
    }

    func dynamicControlDescriptor(
        of element: AXUIElement
    ) -> DynamicControlDescriptor? {
        guard
            let window = accessibilityElementAttribute(
                kAXWindowAttribute,
                of: element
            )
        else {
            return nil
        }
        let leaf: DynamicControlSemanticSignature.Node
        switch dynamicComposerLeafObservation(for: element) {
        case .leaf(let observedLeaf):
            leaf = observedLeaf
        case .ineligible, .unknown:
            return nil
        }

        var ancestors: [DynamicControlSemanticSignature.Node] = []
        var cursor = element
        var reachedWindow = false
        for _ in 0..<64 {
            guard
                let parent = accessibilityElementAttribute(
                    kAXParentAttribute,
                    of: cursor
                )
            else {
                return nil
            }
            if CFEqual(parent, window) {
                reachedWindow = true
                break
            }
            switch semanticNodeObservation(for: parent) {
            case .node(let node):
                ancestors.append(node)
            case .unknown:
                return nil
            }
            cursor = parent
        }
        guard reachedWindow else { return nil }
        return DynamicControlDescriptor(
            window: window,
            semanticSignature: .normalizedComposer(
                leafSubrole: leaf.subrole,
                leafIdentifier: leaf.identifier,
                ancestors: ancestors
            )
        )
    }

    private func accessibilityElementAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                attribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)  // swiftlint:disable:this force_cast
    }

    /// Codex and Claude can expose the same empty composer as a text-like
    /// AXGroup, then replace it with AXTextArea once content exists. Normalize
    /// those two proven renderer shapes to one leaf family, while rejecting the
    /// many ancestor groups/web areas that only advertise selected-range.
    private func dynamicComposerLeafObservation(
        for element: AXUIElement
    ) -> DynamicComposerLeafObservation {
        var roleValue: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        let role = roleValue as? String
        let isTextLikeRole = role == "AXTextArea" || role == "AXGroup"
        let rangeSettable =
            isTextLikeRole
            ? selectedTextRangeSettable(on: element)
            : nil
        let count = isTextLikeRole ? characterCount(in: element) : nil
        switch dynamicEditableLeafEligibility(
            roleReadSucceeded: roleStatus == .success,
            role: role,
            selectedTextRangeSettable: rangeSettable,
            characterCount: count
        ) {
        case .ineligible:
            return .ineligible
        case .unknown:
            return .unknown
        case .eligible:
            break
        }
        guard let role else { return .unknown }
        switch role {
        case "AXTextArea":
            break
        case "AXGroup":
            // The empty Codex composer is occasionally app-focused as the
            // editable group immediately inside its AXTextArea. No equivalent
            // shape has been observed in Claude, so do not broaden it there.
            var pid = pid_t()
            guard AXUIElementGetPid(element, &pid) == .success else {
                return .unknown
            }
            guard
                NSRunningApplication(processIdentifier: pid)?
                    .bundleIdentifier == "com.openai.codex"
            else {
                return .ineligible
            }
            guard
                let applicationFocused = isApplicationFocused(
                    element,
                    processIdentifier: pid
                )
            else {
                return .unknown
            }
            guard applicationFocused else { return .ineligible }
            switch nearestNonGroupAncestorBeforeWebArea(of: element) {
            case .role("AXTextArea"):
                break
            case .role, .reachedWebArea:
                return .ineligible
            case .unknown:
                return .unknown
            }
        default:
            return .ineligible
        }
        let subrole: String?
        switch optionalSemanticStringAttribute(
            kAXSubroleAttribute,
            of: element
        ) {
        case .value(let value): subrole = value
        case .unknown: return .unknown
        }
        let identifier: String?
        switch optionalSemanticStringAttribute("AXIdentifier", of: element) {
        case .value(let value): identifier = value
        case .unknown: return .unknown
        }
        return .leaf(
            DynamicControlSemanticSignature.Node(
                role: "AXDynamicComposerText",
                subrole: subrole,
                identifier: identifier
            ))
    }

    private func selectedTextRangeSettable(
        on element: AXUIElement
    ) -> Bool? {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &settable
        )
        switch status {
        case .success:
            return settable.boolValue
        case .attributeUnsupported, .noValue:
            return false
        default:
            return nil
        }
    }

    private func isApplicationFocused(
        _ element: AXUIElement,
        processIdentifier: pid_t
    ) -> Bool? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application,
                kAXFocusedUIElementAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return CFEqual(value, element)
    }

    private func nearestNonGroupAncestorBeforeWebArea(
        of element: AXUIElement
    ) -> DynamicAncestorObservation {
        var cursor = element
        for _ in 0..<64 {
            guard
                let parent = accessibilityElementAttribute(
                    kAXParentAttribute,
                    of: cursor
                )
            else {
                return .unknown
            }
            let role: String
            switch requiredSemanticStringAttribute(
                kAXRoleAttribute,
                of: parent
            ) {
            case .value(let observedRole?): role = observedRole
            case .value(nil), .unknown: return .unknown
            }
            if role == "AXWebArea" { return .reachedWebArea }
            if role != "AXGroup" { return .role(role) }
            cursor = parent
        }
        return .unknown
    }

    private func semanticNodeObservation(
        for element: AXUIElement
    ) -> SemanticNodeObservation {
        let role: String
        switch requiredSemanticStringAttribute(kAXRoleAttribute, of: element) {
        case .value(let observedRole?): role = observedRole
        case .value(nil), .unknown: return .unknown
        }
        let subrole: String?
        switch optionalSemanticStringAttribute(
            kAXSubroleAttribute,
            of: element
        ) {
        case .value(let value): subrole = value
        case .unknown: return .unknown
        }
        let identifier: String?
        switch optionalSemanticStringAttribute("AXIdentifier", of: element) {
        case .value(let value): identifier = value
        case .unknown: return .unknown
        }
        return .node(
            DynamicControlSemanticSignature.Node(
                role: role,
                subrole: subrole,
                identifier: identifier
            ))
    }

    private func requiredSemanticStringAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> DynamicSemanticStringObservation {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        guard status == .success,
            let string = value as? String,
            !string.isEmpty
        else {
            return .unknown
        }
        return .value(string)
    }

    private func optionalSemanticStringAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> DynamicSemanticStringObservation {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        return dynamicSemanticStringObservation(status: status, value: value)
    }

    func fieldValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &value
            ) == .success
        else { return nil }
        return value as? String
    }

    func pasteboardChangeCount() -> Int {
        NSPasteboard.general.changeCount
    }

    func insertViaSelectedText(
        _ text: String,
        into element: AXUIElement,
        validateBeforeWrite: () throws -> Void,
        commitDelivery: () throws -> Void
    ) throws -> AXInsertionVerification {
        var settable = DarwinBoolean(false)
        let query = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard query == .success, settable.boolValue else { return .notAttempted }

        // Attribute support can be queried before the target changes. Reacquire
        // and validate the focused control at the last possible boundary before
        // writing, just as the paste path does before posting Cmd+V.
        try validateBeforeWrite()

        // A direct write is attempted only at a collapsed caret with a known
        // character count, observed after final target validation. Selected
        // replacements can preserve total length, and a caret without a count
        // cannot distinguish delivery from a silent no-op. Refusing before the
        // setter keeps a verified paste fallback safe.
        let beforeRange = selectedTextRange(of: element)
        let beforeCharacterCount = characterCount(in: element)
        // Both evidence reads above are blocking AX calls. Focus can move to a
        // different or secure control while either call is in flight, so prove
        // the exact non-secure target again before interpreting the evidence or
        // invoking the setter. The validator is intentionally idempotent.
        try validateBeforeWrite()
        guard
            AXInsertionVerification.canAttempt(
                beforeRange: beforeRange,
                beforeCharacterCount: beforeCharacterCount,
                insertedUTF16Count: text.utf16.count
            )
        else {
            return .notAttempted
        }

        try commitDelivery()
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard result == .success else { return .outcomeUnknown }

        // AX writes may be applied asynchronously. Poll briefly, but only
        // return confirmed when observable state matches the exact edit.
        let deadline = Date().addingTimeInterval(0.4)
        var verification: AXInsertionVerification = .outcomeUnknown
        repeat {
            usleep(25_000)
            verification = AXInsertionVerification.evaluate(
                beforeRange: beforeRange,
                afterRange: selectedTextRange(of: element),
                beforeCharacterCount: beforeCharacterCount,
                afterCharacterCount: characterCount(in: element),
                insertedUTF16Count: text.utf16.count
            )
            if verification == .confirmed {
                return .confirmed
            }
        } while Date() < deadline
        return verification
    }

    func pasteboardInsert(
        _ text: String,
        into element: AXUIElement,
        targetPID: pid_t,
        restoreClipboard: Bool,
        pasteboardLeaseAlreadyHeld: Bool,
        validateBeforeStaging: () throws -> Void,
        validateBeforeGlobalEvent: () throws -> Void,
        commitDelivery: () throws -> Void,
        resolveTargetAtGlobalEvent: (() throws -> DynamicPasteTargetEvidence)?,
        resolveVerificationTargetAfterPaste: (() throws -> DynamicPasteTargetEvidence?)?
    ) throws -> PasteVerification {
        let acquiredLease = !pasteboardLeaseAlreadyHeld
        if acquiredLease,
            !PasteboardTransactionGate.shared.tryAcquire()
        {
            throw InsertionError.insertionRejected
        }
        defer {
            if acquiredLease {
                PasteboardTransactionGate.shared.release()
            }
        }
        return try withStagedPasteboardString(
            text,
            on: .general,
            restoreClipboard: restoreClipboard,
            validateBeforeStaging: validateBeforeStaging
        ) { validateStagedOwnership in
            // Event objects are prepared before this validation runs, keeping the
            // check at the final boundary immediately before Cmd+V is posted.
            var eventTarget = element
            var before: CFRange?
            return try performSynchronousPasteEventTransport(
                validateStagedOwnership: validateStagedOwnership,
                postEvent: { validateOwnershipAtEvent in
                    try postCommandV(
                        to: targetPID,
                        validateBeforeGlobalEvent: {
                            try validateBeforeGlobalEvent()
                            if let resolveTargetAtGlobalEvent {
                                let evidence = try resolveTargetAtGlobalEvent()
                                eventTarget = evidence.element
                                before = evidence.selectedTextRange
                            } else {
                                // Exact-control delivery retains its fixed
                                // verification handle, including the own-Home
                                // path.
                                before = selectedTextRange(of: eventTarget)
                                // The range observation is itself a blocking AX
                                // call. Re-prove the exact non-secure target
                                // after it returns and before the final staged-
                                // clipboard ownership check and one event.
                                try validateBeforeGlobalEvent()
                            }
                            // This must be the last operation before event
                            // dispatch. A same-length external replacement could
                            // otherwise falsely satisfy the caret-only receipt.
                            try validateOwnershipAtEvent()
                            try commitDelivery()
                        }
                    )
                },
                receipt: { validateOwnershipDuringReceipt in
                    if let before {
                        // Poll until AX confirms the exact UTF-16 caret move. A
                        // dynamic editor may rebuild its focused proxy after paste.
                        let insertedCount = text.utf16.count
                        let deadline = Date().addingTimeInterval(0.4)
                        var accumulator = PasteVerificationAccumulator()
                        repeat {
                            usleep(25_000)
                            try validateOwnershipDuringReceipt()
                            let after: CFRange?
                            if let resolveVerificationTargetAfterPaste {
                                // Missing proxy evidence is transient while a
                                // dynamic editor remounts its composer. Policy
                                // violations remain terminal.
                                after = try resolveVerificationTargetAfterPaste()?
                                    .selectedTextRange
                            } else {
                                // Cmd+V has already been dispatched, but the
                                // exact target can still move or become secure
                                // while receipt polling blocks in AX. Surround
                                // every range read with the same exact security
                                // proof; the shared transport promotes any
                                // resulting sensitive error to a post-event,
                                // no-retry outcome.
                                try validateBeforeGlobalEvent()
                                after = selectedTextRange(of: eventTarget)
                                try validateBeforeGlobalEvent()
                            }
                            try validateOwnershipDuringReceipt()
                            if accumulator.observe(
                                before: before,
                                after: after,
                                insertedUTF16Count: insertedCount
                            ) {
                                return .confirmed
                            }
                        } while Date() < deadline
                        return accumulator.result
                    }

                    // Preserve the delivery window before restoring the clipboard,
                    // but make the lack of confirmation explicit upstream.
                    usleep(150_000)
                    // Even without baseline range evidence, the receipt delay
                    // is a post-event window in which exact focus can move to
                    // a secure or unreadable target. Revalidate before
                    // classifying the delivery as merely unavailable.
                    try validateBeforeGlobalEvent()
                    try validateOwnershipDuringReceipt()
                    return .unavailable
                }
            )
        }
    }

    @MainActor
    func pasteboardInsertDynamic(
        _ text: String,
        targetPID: pid_t,
        restoreClipboard: Bool,
        validateBeforeStaging: @escaping () throws -> Void,
        commitDelivery: @escaping () throws -> Void,
        resolveTargetAtGlobalEvent:
            @escaping () async throws -> DynamicPasteTargetEvidence,
        validateResolvedTargetAtGlobalEvent:
            @escaping (DynamicPasteTargetEvidence) throws -> Void,
        resolveVerificationTargetAfterPaste:
            @escaping () throws -> DynamicPasteTargetEvidence?
    ) async throws -> PasteVerification {
        try await performDynamicPasteTransport(
            text: text,
            validateBeforeStaging: validateBeforeStaging,
            resolveTargetAtGlobalEvent: resolveTargetAtGlobalEvent,
            stage: { validation, operation in
                try await withStagedPasteboardString(
                    text,
                    on: .general,
                    restoreClipboard: restoreClipboard,
                    validateBeforeStaging: validation,
                    operation: operation
                )
            },
            postEvent: { evidence, validateStagedOwnership in
                try self.postCommandV(
                    to: targetPID,
                    validateBeforeGlobalEvent: {
                        try Task.checkCancellation()
                        try validateResolvedTargetAtGlobalEvent(evidence)
                        try validateStagedOwnership()
                        try commitDelivery()
                    }
                )
            },
            resolveVerificationTargetAfterPaste:
                resolveVerificationTargetAfterPaste,
            receiptDelay: {
                try await Task.sleep(nanoseconds: 25_000_000)
            },
            acquiresPasteboardLease: false
        )
    }

    func postUndoKeystroke(
        validateBeforeGlobalEvent: () throws -> Void
    ) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let zKey: CGKeyCode = 6  // kVK_ANSI_Z
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: zKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: zKey, keyDown: false)
        keyUp?.flags = .maskCommand
        try validateBeforeGlobalEvent()
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        var range = CFRange()
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func characterCount(in element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXNumberOfCharactersAttribute as CFString,
                &value
            ) == .success,
            let number = value as? NSNumber
        else {
            return nil
        }
        return number.intValue
    }

    private func postCommandV(
        to targetPID: pid_t,
        validateBeforeGlobalEvent: () throws -> Void
    ) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9  // kVK_ANSI_V
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: vKey,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: vKey,
                keyDown: false
            )
        else {
            throw InsertionError.insertionRejected
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        // A caller-side check before clipboard staging is not sufficient:
        // focus or PID identity can change while the global event is prepared.
        try validateBeforeGlobalEvent()
        // Route the keystroke to the already validated application instead of
        // broadcasting it at the session event tap. The target must still be
        // frontmost and the exact focused control is revalidated immediately
        // above, but PID routing removes a final scheduler window in which a
        // global event could be received by an unrelated process.
        keyDown.postToPid(targetPID)
        keyUp.postToPid(targetPID)
    }
}

/// Inserts text into another application's focused field.
/// Strategy order: AX selected-text write (no clipboard touch) → verified
/// pasteboard + Cmd+V with save/restore. Secure fields are refused.
public final class TextInserter: @unchecked Sendable {
    private let environment: any TextInsertionEnvironment
    private let captureReadinessDelay: (UInt64) async throws -> Void

    /// Codex and Claude Desktop rebuild the Accessibility proxy for their
    /// composers during normal focus and paste transitions. Ordinary dictation
    /// may follow that current focused control only while the original app
    /// remains frontmost and its activation generation is unchanged. No other
    /// app inherits this policy.
    private static let dynamicFocusedControlBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop",
        "com.openai.codex",
    ]
    /// Capture may wait longer than delivery because no microphone, clipboard,
    /// or key event exists yet. Dynamic renderers sometimes need more than the
    /// legacy 500 ms window to publish a coherent focused-control path.
    private static let dynamicCaptureReadinessAttempts = 80
    private static let dynamicCaptureReadinessTimeout: Duration = .seconds(2)
    private static let dynamicReadinessAttempts = 20
    private static let dynamicReadinessDelayNanoseconds: UInt64 = 25_000_000

    public init() {
        self.environment = MacTextInsertionEnvironment()
        self.captureReadinessDelay = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    init(
        environment: any TextInsertionEnvironment,
        captureReadinessDelay: @escaping (UInt64) async throws -> Void = {
            nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.environment = environment
        self.captureReadinessDelay = captureReadinessDelay
    }

    public static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Content-free, non-retaining check for an explicitly secure field at a
    /// recording boundary. Unknown or temporarily unavailable Accessibility
    /// evidence does not become a target lock or block microphone capture; the
    /// full delivery transaction still fails closed before any text write.
    public func isExplicitSecureFieldFocused(
        for focusLock: InsertionFocusLock
    ) -> Bool {
        guard environment.isTrusted(),
            focusLock.matches(
                processIdentifier: focusLock.processIdentifier,
                bundleIdentifier: environment.bundleIdentifier(
                    for: focusLock.processIdentifier
                ),
                appName: environment.appName(for: focusLock.processIdentifier)
            ),
            isFocusCompatible(with: focusLock),
            let element = environment.focusedElement(
                for: focusLock.processIdentifier
            )
        else {
            return false
        }
        return environment.secureFieldClassification(
            element,
            textCapabilityKnown: false
        ) == .secure
    }

    /// Validates a target at an explicit diagnostic or protected-workflow
    /// boundary. This reads only identity and secure-field metadata; it never
    /// reads field contents or performs a write. A missing focused control fails
    /// closed because its secure status cannot be proven.
    public func preflight(_ focusLock: InsertionFocusLock) throws {
        _ = try captureTarget(focusLock)
    }

    /// The app's single field-content read, existing only for the opt-in
    /// "learn corrections from your edits" feature: after a dictation is
    /// inserted, the enabled watch briefly re-reads the exact control it wrote
    /// into so the person's own fix can be compared with what was inserted.
    /// Reads are refused for secure fields, return nil when the control no
    /// longer exists or exposes no text value, and must only be made while
    /// the person has the setting turned on. The value is compared in memory
    /// and never persisted, logged, or transmitted.
    public func editWatchValue(of target: CapturedInsertionTarget) -> String? {
        let element = target.control.element
        guard (try? validateExactNonsecureTextControl(element)) != nil else {
            return nil
        }
        return environment.fieldValue(of: element)
    }

    /// Freezes the exact focused control together with the existing application
    /// identity lock. Capture fails closed when Accessibility permission,
    /// application identity, focus, control availability, or secure status
    /// cannot be proven. No field value or selected text is read.
    public func captureTarget(
        _ focusLock: InsertionFocusLock
    ) throws -> CapturedInsertionTarget {
        guard environment.isTrusted() else { throw InsertionError.accessibilityNotTrusted }
        try verifyIdentity(of: focusLock)
        guard isFocusCompatible(with: focusLock) else { throw InsertionError.focusChanged }
        let element = try safeFocusedElement(for: focusLock.processIdentifier)

        // Reacquire once more before returning so a control that disappears,
        // changes, or becomes secure during capture is never frozen as valid.
        try revalidateFinalTarget(
            focusLock,
            expectedElement: element,
            allowsOwnOverlay: true,
            expectsCapturedControl: true
        )
        return CapturedInsertionTarget(focusLock: focusLock, element: element)
    }

    /// Captures ordinary dictation's target contract. Codex and Claude freeze a
    /// logical application destination after two independent observations of a
    /// non-secure, text-capable app-focused control. The observations need not
    /// return equal AX proxies and never read the selected-range value or child
    /// `AXFocused` attribute. A temporarily absent app-focused element or text
    /// capability is retried within a bounded window while application identity,
    /// frontmost PID, activation generation, cancellation, and secure state stay
    /// terminal. Protected workflows keep using `captureTarget(_:)` directly.
    @MainActor
    public func captureTargetRecoveringFromSameApplicationFieldDrift(
        _ focusLock: InsertionFocusLock,
        shouldContinue: () -> Bool = { true }
    ) async throws -> CapturedInsertionTarget {
        if Self.dynamicFocusedControlBundleIDs.contains(
            focusLock.bundleIdentifier
        ),
            environment.frontmostProcessIdentifier()
                == focusLock.processIdentifier
        {
            return try await captureDynamicApplicationTarget(
                focusLock,
                shouldContinue: shouldContinue
            )
        }

        do {
            return try captureTarget(focusLock)
        } catch let error as InsertionError
            where error == .focusChanged || error == .targetFieldChanged
        {
            try verifyIdentity(of: focusLock)
            guard
                environment.currentActivationGeneration()
                    == focusLock.activationGeneration,
                isFocusCompatible(with: focusLock)
            else {
                throw InsertionError.focusChanged
            }

            FlowLog.info(
                "focused control changed during capture preflight; retrying once in the same application"
            )
            await Task.yield()
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            guard
                environment.currentActivationGeneration()
                    == focusLock.activationGeneration
            else {
                throw InsertionError.focusChanged
            }
            if Self.dynamicFocusedControlBundleIDs.contains(
                focusLock.bundleIdentifier
            ),
                environment.frontmostProcessIdentifier()
                    == focusLock.processIdentifier
            {
                return try await captureDynamicApplicationTarget(
                    focusLock,
                    shouldContinue: shouldContinue
                )
            }
            let target = try captureTarget(focusLock)
            guard
                environment.currentActivationGeneration()
                    == focusLock.activationGeneration
            else {
                throw InsertionError.focusChanged
            }
            return target
        }
    }

    /// Bounded target resolution for the exact dynamic allowlist. Two coherent
    /// observations of the focused control path identify one logical editor
    /// without walking the rest of the window. Renderer churn is safe to retry;
    /// application identity, activation generation, cancellation, and explicit
    /// secure state remain terminal.
    @MainActor
    private func captureDynamicApplicationTarget(
        _ focusLock: InsertionFocusLock,
        shouldContinue: () -> Bool
    ) async throws -> CapturedInsertionTarget {
        guard environment.isTrusted() else {
            throw InsertionError.accessibilityNotTrusted
        }
        let readinessClock = ContinuousClock()
        let readinessDeadline = readinessClock.now.advanced(
            by: Self.dynamicCaptureReadinessTimeout
        )
        var lastTransientError: InsertionError = .insertionRejected
        var lastTransientStage: DynamicCaptureReadinessStage?
        let noteTransient: (DynamicCaptureReadinessStage) -> Void = {
            lastTransientStage = $0
        }
        for attempt in 0..<Self.dynamicCaptureReadinessAttempts {
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            do {
                let initial = try currentDynamicTextCapableSnapshot(
                    for: focusLock,
                    noteTransient: noteTransient
                )
                let current = try currentDynamicTextCapableSnapshot(
                    for: focusLock,
                    noteTransient: noteTransient
                )
                guard
                    CFEqual(
                        initial.descriptor.window,
                        current.descriptor.window
                    ),
                    initial.descriptor.semanticSignature
                        == current.descriptor.semanticSignature
                else {
                    noteTransient(.stability)
                    throw InsertionError.targetFieldChanged
                }
                let identity = CapturedDynamicTargetIdentity(
                    window: current.descriptor.window,
                    semanticSignature: current.descriptor.semanticSignature
                )
                // The focused-path observations may complete synchronously on
                // the main actor. Yield once so queued hold-release or workspace
                // activation callbacks become visible before this target can
                // authorize the next workflow boundary.
                await Task.yield()
                try Task.checkCancellation()
                guard shouldContinue() else { throw CancellationError() }
                try revalidateDynamicApplication(focusLock)
                let final = try currentDynamicTextCapableSnapshot(
                    for: focusLock,
                    matching: identity,
                    noteTransient: noteTransient
                )
                return CapturedInsertionTarget(
                    focusLock: focusLock,
                    element: final.element,
                    contract: .dynamicApplication(identity)
                )
            } catch let error as InsertionError {
                switch error {
                case .insertionRejected, .targetSecurityUnverifiable,
                    .targetFieldChanged:
                    lastTransientError = error
                default:
                    throw error
                }
            }

            guard attempt < Self.dynamicCaptureReadinessAttempts - 1,
                readinessClock.now < readinessDeadline
            else { break }
            try await captureReadinessDelay(
                Self.dynamicReadinessDelayNanoseconds
            )
            guard readinessClock.now < readinessDeadline else { break }
        }
        FlowLog.info(
            "dynamic capture readiness exhausted; transientStageObserved=\(lastTransientStage != nil)"
        )
        throw lastTransientError
    }

    /// Prepares a frozen external destination for ordinary dictation delivery.
    /// A normal app launch can leave Home frontmost while the tracker still
    /// holds the exact external app that was active immediately before launch.
    /// In that one state, return to the frozen PID first, then
    /// wait briefly for the app-level focused element to become observable. For
    /// dynamic editors, only structural text capability is needed here; the
    /// concrete selected range is deliberately deferred until delivery.
    ///
    /// A different external app, changed activation generation, terminated or
    /// relaunched target, secure control, missing focus, or persistent missing
    /// text capability all fail closed. Protected callers can retain an
    /// exact-control preflight without reactivation.
    @MainActor
    public func prepareTargetForOrdinaryCapture(
        _ focusLock: InsertionFocusLock,
        shouldContinue: () -> Bool = { true }
    ) async throws -> CapturedInsertionTarget {
        guard shouldContinue() else { throw CancellationError() }
        guard environment.isTrusted() else {
            throw InsertionError.accessibilityNotTrusted
        }
        try verifyIdentity(of: focusLock)
        guard
            environment.currentActivationGeneration()
                == focusLock.activationGeneration
        else {
            throw InsertionError.focusChanged
        }

        let targetPID = focusLock.processIdentifier
        let initialFrontmostPID = environment.frontmostProcessIdentifier()
        if initialFrontmostPID == targetPID {
            return try await captureTargetRecoveringFromSameApplicationFieldDrift(
                focusLock,
                shouldContinue: shouldContinue
            )
        }
        guard initialFrontmostPID == environment.ownProcessIdentifier() else {
            throw InsertionError.focusChanged
        }

        // Let queued workspace activation and hold-release events reach the main
        // actor before requesting focus. This prevents our request from hiding a
        // different user-selected app whose notification was already in flight.
        try await captureReadinessDelay(25_000_000)
        try Task.checkCancellation()
        guard shouldContinue() else { throw CancellationError() }
        try verifyIdentity(of: focusLock)
        guard
            environment.frontmostProcessIdentifier()
                == environment.ownProcessIdentifier(),
            environment.currentActivationGeneration()
                == focusLock.activationGeneration
        else {
            throw InsertionError.focusChanged
        }

        // This bounded request does not queue an application reopen. Success is
        // decided solely from observed frontmost PID and frozen target evidence.
        try await environment.requestApplicationActivation(
            processIdentifier: targetPID
        )
        try Task.checkCancellation()
        guard shouldContinue() else { throw CancellationError() }

        // Activation and Electron/browser AX publication are asynchronous.
        // Dynamic editors receive an 80-attempt focused-path window with a
        // two-second soft budget checked between synchronous AX observations;
        // stable editors retain the established 20-observation window and
        // collapsed-caret gate.
        let usesDynamicCaptureReadiness = Self.dynamicFocusedControlBundleIDs
            .contains(focusLock.bundleIdentifier)
        let readinessAttempts =
            usesDynamicCaptureReadiness
            ? Self.dynamicCaptureReadinessAttempts
            : Self.dynamicReadinessAttempts
        let readinessClock = ContinuousClock()
        let readinessDeadline = readinessClock.now.advanced(
            by: Self.dynamicCaptureReadinessTimeout
        )
        var lastTransientError: InsertionError = .insertionRejected
        var lastTransientStage: DynamicCaptureReadinessStage?
        let noteTransient: (DynamicCaptureReadinessStage) -> Void = {
            lastTransientStage = $0
        }
        for attempt in 0..<readinessAttempts {
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            try verifyIdentity(of: focusLock)
            guard
                environment.currentActivationGeneration()
                    == focusLock.activationGeneration
            else {
                throw InsertionError.focusChanged
            }

            let frontmostPID = environment.frontmostProcessIdentifier()
            if frontmostPID == targetPID {
                do {
                    let captured = try captureReadyTargetForOrdinaryHomeRecovery(
                        focusLock,
                        noteTransient: noteTransient
                    )
                    // Focused-path observation can finish without suspending the
                    // main actor. Flush queued hold-release and workspace
                    // notifications before returning a target that may open the
                    // microphone.
                    await Task.yield()
                    try Task.checkCancellation()
                    guard shouldContinue() else { throw CancellationError() }
                    try verifyIdentity(of: focusLock)
                    guard environment.frontmostProcessIdentifier() == targetPID,
                        environment.currentActivationGeneration()
                            == focusLock.activationGeneration
                    else {
                        throw InsertionError.focusChanged
                    }
                    return try revalidateOrdinaryHomeCaptureAfterYield(
                        captured,
                        focusLock: focusLock,
                        noteTransient: noteTransient
                    )
                } catch let error as InsertionError {
                    switch error {
                    case .targetFieldChanged where usesDynamicCaptureReadiness:
                        noteTransient(.stability)
                        lastTransientError = error
                    case .secureField, .accessibilityNotTrusted,
                        .noTargetApplication, .insertionUnverified,
                        .accessibilityInsertionUnverifiedPreservingClipboard,
                        .sensitiveInsertionUnverified, .focusChanged,
                        .targetFieldChanged,
                        .clipboardRestorationUnverified,
                        .insertionAndClipboardRestorationUnverified,
                        .sensitiveClipboardRestorationUnverifiedBeforeInsertion,
                        .sensitiveClipboardRestorationUnverifiedAfterInsertionBegan,
                        .clipboardChangedBeforeInsertion,
                        .clipboardChangedAfterInsertionBegan:
                        throw error
                    case .insertionRejected, .targetSecurityUnverifiable:
                        lastTransientError = error
                    }
                }
            } else if frontmostPID != environment.ownProcessIdentifier() {
                throw InsertionError.focusChanged
            }

            guard attempt < readinessAttempts - 1,
                !usesDynamicCaptureReadiness
                    || readinessClock.now < readinessDeadline
            else { break }
            try await captureReadinessDelay(
                Self.dynamicReadinessDelayNanoseconds
            )
            if usesDynamicCaptureReadiness,
                readinessClock.now >= readinessDeadline
            {
                break
            }
        }

        guard environment.frontmostProcessIdentifier() == targetPID else {
            throw InsertionError.focusChanged
        }
        if usesDynamicCaptureReadiness {
            FlowLog.info(
                "dynamic home capture readiness exhausted; transientStageObserved=\(lastTransientStage != nil)"
            )
        }
        throw lastTransientError
    }

    /// Captures readiness after Home reactivation. Dynamic editors prove text
    /// capability without reading a range value; stable targets retain the
    /// existing exact-control collapsed-caret evidence.
    private func captureReadyTargetForOrdinaryHomeRecovery(
        _ focusLock: InsertionFocusLock,
        noteTransient: ((DynamicCaptureReadinessStage) -> Void)? = nil
    ) throws -> CapturedInsertionTarget {
        if Self.dynamicFocusedControlBundleIDs.contains(
            focusLock.bundleIdentifier
        ) {
            let initial = try currentDynamicTextCapableSnapshot(
                for: focusLock,
                noteTransient: noteTransient
            )
            let current = try currentDynamicTextCapableSnapshot(
                for: focusLock,
                noteTransient: noteTransient
            )
            guard CFEqual(initial.descriptor.window, current.descriptor.window),
                initial.descriptor.semanticSignature
                    == current.descriptor.semanticSignature
            else {
                noteTransient?(.stability)
                throw InsertionError.targetFieldChanged
            }
            let identity = CapturedDynamicTargetIdentity(
                window: current.descriptor.window,
                semanticSignature: current.descriptor.semanticSignature
            )
            let final = try currentDynamicTextCapableSnapshot(
                for: focusLock,
                matching: identity,
                noteTransient: noteTransient
            )
            return CapturedInsertionTarget(
                focusLock: focusLock,
                element: final.element,
                contract: .dynamicApplication(identity)
            )
        }

        let target = try captureTarget(focusLock)
        guard let range = environment.selectedTextRange(of: target.control.element),
            range.location >= 0,
            range.length == 0
        else {
            throw InsertionError.insertionRejected
        }
        try revalidateFinalTarget(
            focusLock,
            expectedElement: target.control.element,
            expectsCapturedControl: true
        )
        return target
    }

    /// Rechecks the contract after Home recovery's explicit callback yield.
    /// Dynamic editors may expose a replacement leaf proxy; exact targets keep
    /// their original control and collapsed-caret requirement.
    private func revalidateOrdinaryHomeCaptureAfterYield(
        _ target: CapturedInsertionTarget,
        focusLock: InsertionFocusLock,
        noteTransient: ((DynamicCaptureReadinessStage) -> Void)? = nil
    ) throws -> CapturedInsertionTarget {
        switch target.contract {
        case .dynamicApplication(let identity):
            let final = try currentDynamicTextCapableSnapshot(
                for: focusLock,
                matching: identity,
                noteTransient: noteTransient
            )
            return CapturedInsertionTarget(
                focusLock: focusLock,
                element: final.element,
                contract: .dynamicApplication(identity)
            )
        case .exactControl:
            try revalidateFinalTarget(
                focusLock,
                expectedElement: target.control.element,
                expectsCapturedControl: true
            )
            guard
                let range = environment.selectedTextRange(
                    of: target.control.element
                ), range.location >= 0, range.length == 0
            else {
                throw InsertionError.insertionRejected
            }
            try revalidateFinalTarget(
                focusLock,
                expectedElement: target.control.element,
                expectsCapturedControl: true
            )
            return target
        }
    }

    /// Returns an interactive Home-window workflow to the exact application and
    /// control captured at its prior explicit boundary. Reactivation is permitted only when
    /// LockedIn Flow itself is frontmost and no different external application
    /// has activated since capture. The control and secure status are checked
    /// before activation and again after the target becomes frontmost.
    @MainActor
    public func restoreFocus(to target: CapturedInsertionTarget) async throws {
        guard environment.isTrusted() else { throw InsertionError.accessibilityNotTrusted }
        let focusLock = target.focusLock
        let targetPID = focusLock.processIdentifier
        try verifyIdentity(of: focusLock)

        if environment.frontmostProcessIdentifier() == targetPID {
            try revalidateFinalTarget(
                focusLock,
                expectedElement: target.control.element,
                expectsCapturedControl: true
            )
            return
        }

        guard environment.frontmostProcessIdentifier() == environment.ownProcessIdentifier(),
            environment.currentActivationGeneration() == focusLock.activationGeneration
        else {
            throw InsertionError.focusChanged
        }
        try revalidateFinalTarget(
            focusLock,
            expectedElement: target.control.element,
            allowsOwnOverlay: true,
            expectsCapturedControl: true
        )

        // Ask the frozen target to return without hiding Home first. Hiding an
        // activating window can expose an unrelated application underneath it,
        // which is neither the user's target nor safe evidence of intent. Some
        // browsers decline activation; those stay on the separately guarded
        // exact-control, PID-routed ordinary-delivery path below.
        let activationAccepted = try await environment.activateApplication(
            processIdentifier: targetPID,
            targetElement: target.control.element
        )
        try Task.checkCancellation()
        if !activationAccepted {
            // Some browser processes refuse programmatic activation even after
            // a user initiated Home action. General dictation may still use
            // its exact-control, PID-routed delivery path while our own window
            // remains frontmost; protected callers independently require the
            // target itself to be frontmost and will reject this fallback.
            guard
                environment.frontmostProcessIdentifier()
                    == environment.ownProcessIdentifier()
            else {
                throw InsertionError.focusChanged
            }
            try revalidateExactControlWithoutFrontmostRequirement(
                focusLock,
                expectedElement: target.control.element
            )
            return
        }

        for attempt in 0..<12 {
            // Give NSWorkspace activation notifications a chance to update the
            // tracker before accepting our own activation request. Without this
            // suspension, a different app activated immediately before this
            // request could be silently overridden while its queued notification
            // had not yet advanced the capture generation.
            try await Task.sleep(nanoseconds: 25_000_000)
            guard
                environment.currentActivationGeneration()
                    == focusLock.activationGeneration
            else {
                throw InsertionError.focusChanged
            }
            if environment.frontmostProcessIdentifier() == targetPID {
                try revalidateFinalTarget(
                    focusLock,
                    expectedElement: target.control.element,
                    expectsCapturedControl: true
                )
                return
            }
            guard attempt < 11 else { break }
        }
        if environment.frontmostProcessIdentifier() == environment.ownProcessIdentifier(),
            environment.currentActivationGeneration() == focusLock.activationGeneration
        {
            try revalidateExactControlWithoutFrontmostRequirement(
                focusLock,
                expectedElement: target.control.element
            )
            return
        }
        throw InsertionError.focusChanged
    }

    /// Restores ordinary dictation while preserving its capture contract. A
    /// logical Codex/Claude target may be reactivated from our own Home window,
    /// then reacquires a non-secure text-capable control without comparing it to
    /// the pre-microphone AX proxy. Protected targets keep the existing
    /// exact-control restoration behavior.
    @MainActor
    public func restoreFocusForOrdinaryDictation(
        to target: CapturedInsertionTarget
    ) async throws -> CapturedInsertionTarget {
        if case .dynamicApplication(let identity) = target.contract {
            return try await restoreDynamicApplicationFocus(
                to: target,
                identity: identity
            )
        }

        do {
            try await restoreFocus(to: target)
            return target
        } catch let error as InsertionError {
            guard
                Self.dynamicFocusedControlBundleIDs.contains(
                    target.focusLock.bundleIdentifier
                ), error == .targetFieldChanged || error == .focusChanged
            else {
                // A stable application's exact field is the destination. Same-
                // app focus drift is never authority to capture a new field.
                throw error
            }
            return try await captureDynamicApplicationTarget(
                target.focusLock,
                shouldContinue: { true }
            )
        }
    }

    /// Reactivates a logical dynamic-editor target only from LockedIn Flow's
    /// own Home window. The captured element is an activation hint, never an
    /// identity requirement. A different external frontmost app or generation
    /// change is terminal, and delivery is not allowed behind our Home window.
    @MainActor
    private func restoreDynamicApplicationFocus(
        to target: CapturedInsertionTarget,
        identity: CapturedDynamicTargetIdentity
    ) async throws -> CapturedInsertionTarget {
        guard environment.isTrusted() else {
            throw InsertionError.accessibilityNotTrusted
        }
        let focusLock = target.focusLock
        let targetPID = focusLock.processIdentifier
        try verifyIdentity(of: focusLock)
        guard
            environment.currentActivationGeneration()
                == focusLock.activationGeneration
        else {
            throw InsertionError.focusChanged
        }

        if environment.frontmostProcessIdentifier() == targetPID {
            _ = try await waitForDynamicTextCapableSnapshot(
                for: focusLock,
                matching: identity
            )
            return target
        }
        guard
            environment.frontmostProcessIdentifier()
                == environment.ownProcessIdentifier()
        else {
            throw InsertionError.focusChanged
        }

        _ = try await environment.activateApplication(
            processIdentifier: targetPID,
            targetElement: target.control.element
        )
        try Task.checkCancellation()

        for attempt in 0..<12 {
            try verifyIdentity(of: focusLock)
            guard
                environment.currentActivationGeneration()
                    == focusLock.activationGeneration
            else {
                throw InsertionError.focusChanged
            }
            let frontmostPID = environment.frontmostProcessIdentifier()
            if frontmostPID == targetPID {
                _ = try await waitForDynamicTextCapableSnapshot(
                    for: focusLock,
                    matching: identity
                )
                return target
            }
            guard frontmostPID == environment.ownProcessIdentifier() else {
                throw InsertionError.focusChanged
            }
            guard attempt < 11 else { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw InsertionError.focusChanged
    }

    /// Apps whose fields accept an AX write and silently ignore it (browser and
    /// webview-backed editors among them). These skip the AX write, but only
    /// after a focused element has been identified and confirmed not to be secure.
    private static let axUnreliableBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "md.obsidian",
        "com.figma.Desktop",
        "us.zoom.xos",
        "com.anthropic.claudefordesktop",
        "com.openai.codex",
    ]

    /// - Parameter restoreClipboard: when false, the pasted text stays on the
    ///   clipboard (auto-copy mode — the user *wants* the dictation there).
    public func insert(
        _ text: String,
        into pid: pid_t,
        restoreClipboard: Bool = true
    ) throws -> InsertionResult {
        guard environment.isTrusted() else { throw InsertionError.accessibilityNotTrusted }

        let bundleID = environment.bundleIdentifier(for: pid)
        return try insertTrusted(
            text,
            into: pid,
            bundleID: bundleID,
            restoreClipboard: restoreClipboard,
            focusLock: nil
        )
    }

    /// Inserts only into the application represented by the supplied focus lock.
    /// A changed, terminated, or relaunched target fails closed; the caller can
    /// preserve the completed transcript for an explicit retry instead of ever
    /// redirecting it to whichever app happens to be active later.
    public func insert(
        _ text: String,
        into focusLock: InsertionFocusLock,
        restoreClipboard: Bool = true
    ) throws -> InsertionResult {
        try insert(
            text,
            into: focusLock,
            restoreClipboard: restoreClipboard,
            pasteboardLeaseAlreadyHeld: false,
            checksTaskCancellation: false
        )
    }

    private func insert(
        _ text: String,
        into focusLock: InsertionFocusLock,
        restoreClipboard: Bool,
        pasteboardLeaseAlreadyHeld: Bool,
        checksTaskCancellation: Bool
    ) throws -> InsertionResult {
        if checksTaskCancellation {
            try Task.checkCancellation()
        }
        guard environment.isTrusted() else { throw InsertionError.accessibilityNotTrusted }

        let pid = focusLock.processIdentifier
        let bundleID = environment.bundleIdentifier(for: pid)
        try verifyIdentity(of: focusLock)
        guard isFocusCompatible(with: focusLock) else { throw InsertionError.focusChanged }
        return try insertTrusted(
            text,
            into: pid,
            bundleID: bundleID,
            restoreClipboard: restoreClipboard,
            focusLock: focusLock,
            capturedElement: nil,
            pasteboardLeaseAlreadyHeld: pasteboardLeaseAlreadyHeld,
            checksTaskCancellation: checksTaskCancellation
        )
    }

    /// Inserts only when the application and exact control captured by an
    /// explicit or protected workflow are still the destination. Unlike the compatibility overloads,
    /// this contract refuses same-application field drift. Protected callers
    /// can additionally prohibit the pasteboard transport and require the
    /// captured application itself (not this app's overlay) to be frontmost.
    public func insert(
        _ text: String,
        into target: CapturedInsertionTarget,
        restoreClipboard: Bool = true,
        allowPasteboardFallback: Bool = true,
        requiresFrontmostTarget: Bool = false
    ) throws -> InsertionResult {
        try insert(
            text,
            into: target,
            restoreClipboard: restoreClipboard,
            allowPasteboardFallback: allowPasteboardFallback,
            requiresFrontmostTarget: requiresFrontmostTarget,
            pasteboardLeaseAlreadyHeld: false,
            checksTaskCancellation: false
        )
    }

    private func insert(
        _ text: String,
        into target: CapturedInsertionTarget,
        restoreClipboard: Bool,
        allowPasteboardFallback: Bool,
        requiresFrontmostTarget: Bool,
        pasteboardLeaseAlreadyHeld: Bool,
        checksTaskCancellation: Bool,
        commitDelivery: () throws -> Void = {}
    ) throws -> InsertionResult {
        if checksTaskCancellation {
            try Task.checkCancellation()
        }
        guard environment.isTrusted() else { throw InsertionError.accessibilityNotTrusted }

        let focusLock = target.focusLock
        let pid = focusLock.processIdentifier
        let bundleID = environment.bundleIdentifier(for: pid)
        try verifyIdentity(of: focusLock)
        guard
            isFocusAllowed(
                with: focusLock,
                requiresFrontmostTarget: requiresFrontmostTarget
            )
        else {
            throw InsertionError.focusChanged
        }
        return try insertTrusted(
            text,
            into: pid,
            bundleID: bundleID,
            restoreClipboard: restoreClipboard,
            focusLock: focusLock,
            capturedElement: target.control.element,
            allowPasteboardFallback: allowPasteboardFallback,
            requiresFrontmostTarget: requiresFrontmostTarget,
            pasteboardLeaseAlreadyHeld: pasteboardLeaseAlreadyHeld,
            checksTaskCancellation: checksTaskCancellation,
            commitDelivery: commitDelivery
        )
    }

    /// Resolves the current safe field and inserts while holding the process-wide
    /// pasteboard transaction lease. Acquiring the lease first prevents a field
    /// token from aging while another paste operation is still in flight.
    /// Ordinary dictation should prefer this API over separately preparing and
    /// inserting a target.
    @MainActor
    public func insertOrdinaryAtCurrentTarget(
        _ text: String,
        into focusLock: InsertionFocusLock,
        restoreClipboard: Bool = true,
        shouldContinue: @escaping () -> Bool = { true },
        commitDelivery: @escaping () throws -> Void = {}
    ) async throws -> OrdinaryInsertionDelivery {
        try await acquirePasteboardTransaction()
        do {
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            let target = try await prepareTargetForOrdinaryCapture(
                focusLock,
                shouldContinue: shouldContinue
            )
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            let guardedCommitDelivery = {
                try Task.checkCancellation()
                guard shouldContinue() else { throw CancellationError() }
                try commitDelivery()
            }
            let result = try await insertOrdinaryHoldingPasteboardLease(
                text,
                into: target,
                restoreClipboard: restoreClipboard,
                commitDelivery: guardedCommitDelivery
            )
            PasteboardTransactionGate.shared.release()
            return OrdinaryInsertionDelivery(result: result, target: target)
        } catch {
            PasteboardTransactionGate.shared.release()
            throw error
        }
    }

    /// Inserts through a target already captured by a protected or explicit
    /// workflow. Ordinary dictation should use
    /// `insertOrdinaryAtCurrentTarget` so target capture occurs after the
    /// pasteboard lease is available.
    @MainActor
    public func insertOrdinary(
        _ text: String,
        into target: CapturedInsertionTarget,
        restoreClipboard: Bool = true,
        commitDelivery: @escaping () throws -> Void = {}
    ) async throws -> InsertionResult {
        try await acquirePasteboardTransaction()
        do {
            try Task.checkCancellation()
            let result = try await insertOrdinaryHoldingPasteboardLease(
                text,
                into: target,
                restoreClipboard: restoreClipboard,
                commitDelivery: commitDelivery
            )
            PasteboardTransactionGate.shared.release()
            return result
        } catch {
            PasteboardTransactionGate.shared.release()
            throw error
        }
    }

    @MainActor
    private func insertOrdinaryHoldingPasteboardLease(
        _ text: String,
        into target: CapturedInsertionTarget,
        restoreClipboard: Bool = true,
        commitDelivery: @escaping () throws -> Void
    ) async throws -> InsertionResult {
        if case .dynamicApplication(let identity) = target.contract {
            return try await insertDynamicOrdinary(
                text,
                into: target,
                identity: identity,
                restoreClipboard: restoreClipboard,
                commitDelivery: commitDelivery
            )
        }

        return try insert(
            text,
            into: target,
            restoreClipboard: restoreClipboard,
            allowPasteboardFallback: true,
            requiresFrontmostTarget: false,
            pasteboardLeaseAlreadyHeld: true,
            checksTaskCancellation: true,
            commitDelivery: commitDelivery
        )
    }

    /// Renderer-backed ordinary delivery is fully asynchronous between target
    /// observations. The clipboard is staged only after the captured logical
    /// destination is re-proved; a stable element/range pair is then polled at
    /// the sole Cmd+V boundary. After that event, polling is receipt-only and
    /// no branch can post another paste.
    @MainActor
    private func insertDynamicOrdinary(
        _ text: String,
        into target: CapturedInsertionTarget,
        identity: CapturedDynamicTargetIdentity,
        restoreClipboard: Bool,
        commitDelivery: @escaping () throws -> Void
    ) async throws -> InsertionResult {
        guard environment.isTrusted() else {
            throw InsertionError.accessibilityNotTrusted
        }
        let focusLock = target.focusLock
        try revalidateDynamicApplication(focusLock)

        // One bounded non-content readiness check before clipboard staging.
        // This admits transient AX publication without ever borrowing a range
        // value from pre-microphone capture.
        _ = try await waitForDynamicTextCapableSnapshot(
            for: focusLock,
            matching: identity
        )

        let verification = try await environment.pasteboardInsertDynamic(
            text,
            targetPID: focusLock.processIdentifier,
            restoreClipboard: restoreClipboard,
            validateBeforeStaging: { [self] in
                _ = try currentDynamicTextCapableSnapshot(
                    for: focusLock,
                    matching: identity
                )
            },
            commitDelivery: commitDelivery,
            resolveTargetAtGlobalEvent: { [self] in
                try await waitForDynamicPasteTargetEvidence(
                    for: focusLock,
                    identity: identity,
                    requiresCollapsedRange: false
                )
            },
            validateResolvedTargetAtGlobalEvent: { [self] evidence in
                try validateDynamicEvidenceAtEvent(
                    evidence,
                    focusLock: focusLock,
                    identity: identity
                )
            },
            resolveVerificationTargetAfterPaste: { [self] in
                do {
                    return try currentDynamicPasteTargetEvidence(
                        for: focusLock,
                        identity: identity,
                        requiresCollapsedRange: true
                    )
                } catch let error as InsertionError
                    where error == .insertionRejected
                {
                    // A remount can transiently hide the receipt proxy. The
                    // environment polls again; no second event is possible.
                    return nil
                }
            }
        )
        return try pasteboardInsertionResult(
            verification: verification,
            charactersInserted: text.count
        )
    }

    private func insertTrusted(
        _ text: String,
        into pid: pid_t,
        bundleID: String,
        restoreClipboard: Bool,
        focusLock: InsertionFocusLock?,
        capturedElement: AXUIElement? = nil,
        allowPasteboardFallback: Bool = true,
        requiresFrontmostTarget: Bool = false,
        pasteboardLeaseAlreadyHeld: Bool = false,
        checksTaskCancellation: Bool = false,
        commitDelivery: () throws -> Void = {}
    ) throws -> InsertionResult {
        if checksTaskCancellation {
            try Task.checkCancellation()
        }
        let skipAX = Self.axUnreliableBundleIDs.contains(bundleID)
        let supportsDynamicFocusedControl =
            focusLock != nil
            && Self.dynamicFocusedControlBundleIDs.contains(bundleID)
            && !requiresFrontmostTarget
        // The exact captured-control contract stays strict until Cmd+V. Only
        // the application-level ordinary retry may refresh before the event.
        let refreshesDynamicControlBeforePaste =
            supportsDynamicFocusedControl
            && capturedElement == nil

        // Always fail closed when Accessibility cannot identify the focused
        // control. Dynamic ordinary delivery bounded-polls only missing
        // app-focus/text-capability evidence while all policy transitions remain
        // terminal. Exact workflows preserve their fixed-control behavior.
        let element: AXUIElement
        let compatibilityDynamicIdentity: CapturedDynamicTargetIdentity?
        let expectsCapturedControl = capturedElement != nil
        if let capturedElement, let focusLock {
            try revalidateFinalTarget(
                focusLock,
                expectedElement: capturedElement,
                allowsOwnOverlay: !requiresFrontmostTarget,
                expectsCapturedControl: true
            )
            element = capturedElement
            compatibilityDynamicIdentity = nil
        } else if refreshesDynamicControlBeforePaste, let focusLock {
            let snapshot = try currentDynamicTextCapableSnapshot(for: focusLock)
            element = snapshot.element
            compatibilityDynamicIdentity = CapturedDynamicTargetIdentity(
                window: snapshot.descriptor.window,
                semanticSignature: snapshot.descriptor.semanticSignature
            )
        } else {
            element = try safeFocusedElement(for: pid, bundleID: bundleID)
            compatibilityDynamicIdentity = nil
        }

        if let focusLock,
            !isFocusAllowed(
                with: focusLock,
                requiresFrontmostTarget: requiresFrontmostTarget
            )
        {
            throw InsertionError.focusChanged
        } else if focusLock == nil {
            try revalidateForegroundTarget(pid, expectedElement: element)
        }
        let expectedElement = capturedElement ?? element
        if !skipAX {
            // Protected delivery prohibits every pasteboard touch, not
            // merely staging. Ordinary AX delivery observes only changeCount so
            // a later auto-copy cannot overwrite an explicit user copy.
            let clipboardChangeCountBeforeAX =
                allowPasteboardFallback
                ? environment.pasteboardChangeCount()
                : nil
            let verification = try environment.insertViaSelectedText(
                text,
                into: element,
                validateBeforeWrite: { [self] in
                    if checksTaskCancellation {
                        try Task.checkCancellation()
                    }
                    if let focusLock {
                        try revalidateFinalTarget(
                            focusLock,
                            expectedElement: expectedElement,
                            allowsOwnOverlay: !requiresFrontmostTarget,
                            expectsCapturedControl: expectsCapturedControl
                        )
                    } else {
                        try revalidateForegroundTarget(pid, expectedElement: expectedElement)
                    }
                },
                commitDelivery: commitDelivery
            )
            let clipboardChangeCountAfterAX =
                allowPasteboardFallback
                ? environment.pasteboardChangeCount()
                : nil
            if verification == .confirmed {
                let disposition: InsertionResult.ClipboardDisposition =
                    if let clipboardChangeCountBeforeAX,
                        let clipboardChangeCountAfterAX
                    {
                        clipboardChangeCountAfterAX == clipboardChangeCountBeforeAX
                            ? .copyIfUnchanged(
                                expectedChangeCount: clipboardChangeCountAfterAX
                            )
                            : .newerExternalContentPreserved
                    } else {
                        .pasteTransportManaged
                    }
                return InsertionResult(
                    method: .accessibilitySelectedText,
                    charactersInserted: text.count,
                    clipboardDisposition: disposition
                )
            }
            // Once the AX setter has been called, an unverified outcome may
            // already have changed the target. Never paste after it because
            // doing so could duplicate content.
            if verification == .outcomeUnknown {
                if let clipboardChangeCountBeforeAX,
                    let clipboardChangeCountAfterAX,
                    clipboardChangeCountAfterAX != clipboardChangeCountBeforeAX
                {
                    throw InsertionError
                        .accessibilityInsertionUnverifiedPreservingClipboard
                }
                throw InsertionError.insertionUnverified
            }
        }

        // Some protected workflows prohibit use of the system pasteboard even
        // for temporary staging. Refuse before calling the environment so the
        // transcript never reaches `NSPasteboard.general` on either skip-AX or
        // rejected-AX paths. Existing insertion APIs retain their default.
        guard allowPasteboardFallback else {
            throw InsertionError.insertionRejected
        }

        // PID-routed delivery may run behind LockedIn Flow's own Home window
        // only for an exact control frozen before capture. Compatibility APIs
        // without that control identity remain frontmost-only. Protected
        // callers also require the target itself frontmost.
        let allowsOwnOverlayPaste = expectsCapturedControl && !requiresFrontmostTarget
        if let focusLock {
            let focusIsValid =
                allowsOwnOverlayPaste
                ? isFocusCompatible(with: focusLock)
                : environment.frontmostProcessIdentifier() == pid
            guard focusIsValid else { throw InsertionError.focusChanged }
        } else if environment.frontmostProcessIdentifier() != pid {
            throw InsertionError.focusChanged
        }
        let resolveTargetAtGlobalEvent: (() throws -> DynamicPasteTargetEvidence)?
        if refreshesDynamicControlBeforePaste, let focusLock,
            let compatibilityDynamicIdentity
        {
            resolveTargetAtGlobalEvent = { [self] in
                try retryDynamicPasteTargetEvidenceSynchronously(
                    for: focusLock,
                    identity: compatibilityDynamicIdentity,
                    requiresCollapsedRange: false
                )
            }
        } else {
            resolveTargetAtGlobalEvent = nil
        }
        let resolveVerificationTargetAfterPaste: (() throws -> DynamicPasteTargetEvidence?)?
        if refreshesDynamicControlBeforePaste, let focusLock,
            let compatibilityDynamicIdentity
        {
            resolveVerificationTargetAfterPaste = { [self] in
                do {
                    return try currentDynamicPasteTargetEvidence(
                        for: focusLock,
                        identity: compatibilityDynamicIdentity,
                        requiresCollapsedRange: true
                    )
                } catch let error as InsertionError {
                    switch error {
                    case .insertionRejected, .targetFieldChanged:
                        // A dynamic editor may briefly publish no
                        // AXFocusedUIElement while it remounts the composer.
                        // Only that absence is retryable.
                        return nil
                    case .secureField, .targetSecurityUnverifiable:
                        // Cmd+V has already been dispatched, so a subsequent
                        // security transition cannot truthfully claim that no
                        // insertion occurred. Preserve sensitive-content
                        // scrubbing while reporting the unknown outcome.
                        throw InsertionError.sensitiveInsertionUnverified
                    default:
                        // Cmd+V has already been dispatched. Any non-secure
                        // policy transition now makes delivery unknowable, so
                        // report the terminal duplicate-prevention outcome
                        // rather than suggesting a blind retry.
                        throw InsertionError.insertionUnverified
                    }
                }
            }
        } else {
            resolveVerificationTargetAfterPaste = nil
        }
        let verification = try environment.pasteboardInsert(
            text,
            into: element,
            targetPID: pid,
            restoreClipboard: restoreClipboard,
            pasteboardLeaseAlreadyHeld: pasteboardLeaseAlreadyHeld,
            validateBeforeStaging: { [self] in
                if checksTaskCancellation {
                    try Task.checkCancellation()
                }
                if let focusLock {
                    if refreshesDynamicControlBeforePaste {
                        _ = try currentDynamicTextCapableSnapshot(
                            for: focusLock,
                            matching: compatibilityDynamicIdentity
                        )
                    } else {
                        try revalidateFinalTarget(
                            focusLock,
                            expectedElement: expectedElement,
                            allowsOwnOverlay: allowsOwnOverlayPaste,
                            expectsCapturedControl: expectsCapturedControl
                        )
                    }
                } else {
                    try revalidateForegroundTarget(pid, expectedElement: expectedElement)
                }
            },
            validateBeforeGlobalEvent: { [self] in
                if checksTaskCancellation {
                    try Task.checkCancellation()
                }
                if let focusLock {
                    if refreshesDynamicControlBeforePaste {
                        // The paired element/range resolver runs immediately
                        // after this invariant check and before the one event.
                        try revalidateDynamicApplication(focusLock)
                    } else {
                        try revalidateFinalTarget(
                            focusLock,
                            expectedElement: expectedElement,
                            allowsOwnOverlay: allowsOwnOverlayPaste,
                            expectsCapturedControl: expectsCapturedControl
                        )
                    }
                } else {
                    try revalidateForegroundTarget(pid, expectedElement: expectedElement)
                }
            },
            commitDelivery: commitDelivery,
            resolveTargetAtGlobalEvent: resolveTargetAtGlobalEvent,
            resolveVerificationTargetAfterPaste: resolveVerificationTargetAfterPaste
        )
        return try pasteboardInsertionResult(
            verification: verification,
            charactersInserted: text.count
        )
    }

    private func pasteboardInsertionResult(
        verification: PasteVerification,
        charactersInserted: Int
    ) throws -> InsertionResult {
        switch verification {
        case .confirmed:
            return InsertionResult(
                method: .pasteboard,
                charactersInserted: charactersInserted
            )
        case .confirmedWithClipboardRestorationUnverified:
            return InsertionResult(
                method: .pasteboard,
                charactersInserted: charactersInserted,
                clipboardDisposition: .pasteTransportRestorationUnverified
            )
        case .unavailable, .rejected:
            throw InsertionError.insertionUnverified
        }
    }

    private func isFocusCompatible(with focusLock: InsertionFocusLock) -> Bool {
        guard let frontmostPID = environment.frontmostProcessIdentifier() else { return false }
        if frontmostPID == focusLock.processIdentifier { return true }
        guard frontmostPID == environment.ownProcessIdentifier() else { return false }
        return environment.currentActivationGeneration() == focusLock.activationGeneration
    }

    private func isFocusAllowed(
        with focusLock: InsertionFocusLock,
        requiresFrontmostTarget: Bool
    ) -> Bool {
        if requiresFrontmostTarget {
            return environment.frontmostProcessIdentifier() == focusLock.processIdentifier
        }
        return isFocusCompatible(with: focusLock)
    }

    /// Voice commands are global keyboard events, so unlike AX text insertion
    /// they require the locked target itself to remain frontmost.
    public func postUndoKeystroke(into focusLock: InsertionFocusLock) throws {
        guard environment.isTrusted() else { throw InsertionError.accessibilityNotTrusted }
        try verifyIdentity(of: focusLock)
        guard environment.frontmostProcessIdentifier() == focusLock.processIdentifier else {
            throw InsertionError.focusChanged
        }
        guard let element = environment.focusedElement(for: focusLock.processIdentifier) else {
            throw InsertionError.insertionRejected
        }
        try validateExactNonsecureTextControl(element)
        try environment.postUndoKeystroke { [self] in
            try revalidateFinalTarget(
                focusLock,
                expectedElement: element
            )
        }
    }

    /// Reacquires the actual focused AX control after event preparation, then
    /// validates identity, target focus, control identity, and secure-field
    /// status at the final boundary before an AX write or global event.
    /// - Parameter expectsCapturedControl: true when `expectedElement` is the
    ///   control frozen at record start. A mismatch is then reported as exact
    ///   field drift; false reports the same race as an application-focus loss.
    private func revalidateFinalTarget(
        _ focusLock: InsertionFocusLock,
        expectedElement: AXUIElement,
        allowsOwnOverlay: Bool = false,
        expectsCapturedControl: Bool = false
    ) throws {
        try verifyIdentity(of: focusLock)
        let focusIsValid =
            allowsOwnOverlay
            ? isFocusCompatible(with: focusLock)
            : environment.frontmostProcessIdentifier() == focusLock.processIdentifier
        guard focusIsValid else {
            throw InsertionError.focusChanged
        }
        guard let currentElement = environment.focusedElement(for: focusLock.processIdentifier)
        else {
            guard allowsOwnOverlay,
                environment.frontmostProcessIdentifier()
                    == environment.ownProcessIdentifier(),
                environment.isElementFocused(expectedElement) == true
            else {
                throw InsertionError.focusChanged
            }
            try validateExactNonsecureTextControl(expectedElement)
            guard environment.isElementFocused(expectedElement) == true else {
                throw InsertionError.focusChanged
            }
            try verifyIdentity(of: focusLock)
            guard isFocusCompatible(with: focusLock) else {
                throw InsertionError.focusChanged
            }
            return
        }
        try validateExactNonsecureTextControl(currentElement)
        guard
            let afterSecurity = environment.focusedElement(
                for: focusLock.processIdentifier
            )
        else {
            throw InsertionError.focusChanged
        }
        try validateExactNonsecureTextControl(afterSecurity)
        guard
            let afterClassification = environment.focusedElement(
                for: focusLock.processIdentifier
            )
        else {
            throw InsertionError.focusChanged
        }
        guard CFEqual(afterClassification, afterSecurity) else {
            try validateExactNonsecureTextControl(afterClassification)
            throw expectsCapturedControl
                ? InsertionError.targetFieldChanged
                : InsertionError.focusChanged
        }
        try verifyIdentity(of: focusLock)
        let focusStillValid =
            allowsOwnOverlay
            ? isFocusCompatible(with: focusLock)
            : environment.frontmostProcessIdentifier()
                == focusLock.processIdentifier
        guard focusStillValid else {
            throw InsertionError.focusChanged
        }
        guard CFEqual(currentElement, afterClassification),
            CFEqual(afterClassification, expectedElement)
        else {
            throw expectsCapturedControl
                ? InsertionError.targetFieldChanged
                : InsertionError.focusChanged
        }
    }

    /// Confirms target identity, exact focused control, and non-secure state
    /// when an activating Home window remains the only frontmost app. This is
    /// used only for PID-routed ordinary delivery; protected insertion still
    /// requires the target process itself to be frontmost.
    private func revalidateExactControlWithoutFrontmostRequirement(
        _ focusLock: InsertionFocusLock,
        expectedElement: AXUIElement
    ) throws {
        try verifyIdentity(of: focusLock)
        guard
            environment.currentActivationGeneration()
                == focusLock.activationGeneration
        else {
            throw InsertionError.focusChanged
        }
        if let currentElement = environment.focusedElement(
            for: focusLock.processIdentifier
        ) {
            try validateExactNonsecureTextControl(currentElement)
            guard
                let afterSecurity = environment.focusedElement(
                    for: focusLock.processIdentifier
                )
            else {
                throw InsertionError.focusChanged
            }
            try validateExactNonsecureTextControl(afterSecurity)
            guard
                let afterClassification = environment.focusedElement(
                    for: focusLock.processIdentifier
                )
            else {
                throw InsertionError.focusChanged
            }
            guard CFEqual(afterClassification, afterSecurity) else {
                try validateExactNonsecureTextControl(afterClassification)
                throw InsertionError.targetFieldChanged
            }
            try verifyIdentity(of: focusLock)
            guard
                environment.currentActivationGeneration()
                    == focusLock.activationGeneration
            else {
                throw InsertionError.focusChanged
            }
            guard CFEqual(currentElement, afterClassification),
                CFEqual(afterClassification, expectedElement)
            else {
                throw InsertionError.targetFieldChanged
            }
            return
        }
        // Some background browsers stop publishing an application-level
        // focused-element attribute even though the exact web control retains
        // its internal AXFocused state. General PID-routed delivery may use
        // that narrower evidence; absence or false still fails closed.
        guard environment.isElementFocused(expectedElement) == true else {
            throw InsertionError.focusChanged
        }
        try validateExactNonsecureTextControl(expectedElement)
        guard environment.isElementFocused(expectedElement) == true else {
            throw InsertionError.focusChanged
        }
        try verifyIdentity(of: focusLock)
        guard
            environment.currentActivationGeneration()
                == focusLock.activationGeneration
        else {
            throw InsertionError.focusChanged
        }
    }

    /// The PID-only compatibility path has no capture-time identity token, so
    /// it is permitted only while the requested process is still frontmost and
    /// the exact non-secure control resolved at the start remains focused.
    private func revalidateForegroundTarget(
        _ pid: pid_t,
        expectedElement: AXUIElement
    ) throws {
        guard environment.frontmostProcessIdentifier() == pid else {
            throw InsertionError.focusChanged
        }
        guard let currentElement = environment.focusedElement(for: pid) else {
            throw InsertionError.focusChanged
        }
        try validateExactNonsecureTextControl(currentElement)
        guard let afterSecurity = environment.focusedElement(for: pid) else {
            throw InsertionError.focusChanged
        }
        try validateExactNonsecureTextControl(afterSecurity)
        guard let afterClassification = environment.focusedElement(for: pid) else {
            throw InsertionError.focusChanged
        }
        guard CFEqual(afterClassification, afterSecurity) else {
            try validateExactNonsecureTextControl(afterClassification)
            throw InsertionError.focusChanged
        }
        guard environment.frontmostProcessIdentifier() == pid,
            CFEqual(currentElement, afterClassification),
            CFEqual(afterClassification, expectedElement)
        else {
            throw InsertionError.focusChanged
        }
    }

    /// Re-proves the immutable portion of the dynamic logical target. Every
    /// dynamic observation runs this both before and after its AX read so a
    /// transition during capability or range enumeration is terminal.
    private func revalidateDynamicApplication(
        _ focusLock: InsertionFocusLock
    ) throws {
        guard
            Self.dynamicFocusedControlBundleIDs.contains(
                focusLock.bundleIdentifier
            )
        else {
            throw InsertionError.targetFieldChanged
        }
        try verifyIdentity(of: focusLock)
        guard
            environment.frontmostProcessIdentifier()
                == focusLock.processIdentifier,
            environment.currentActivationGeneration()
                == focusLock.activationGeneration
        else {
            throw InsertionError.focusChanged
        }
    }

    private func dynamicDescriptor(
        _ descriptor: DynamicControlDescriptor,
        matches identity: CapturedDynamicTargetIdentity
    ) -> Bool {
        CFEqual(descriptor.window, identity.window)
            && descriptor.semanticSignature == identity.semanticSignature
    }

    /// Every dynamic AX read is surrounded by immutable application-policy
    /// checks. In particular, the check after the read prevents a queued
    /// away/back activation from being hidden by a subsequently safe-looking
    /// focused element.
    private func currentDynamicFocusedElement(
        for focusLock: InsertionFocusLock,
        noteTransient: ((DynamicCaptureReadinessStage) -> Void)? = nil
    ) throws -> AXUIElement {
        try revalidateDynamicApplication(focusLock)
        guard
            let element = environment.focusedElement(
                for: focusLock.processIdentifier
            )
        else {
            noteTransient?(.focusedElement)
            try revalidateDynamicApplication(focusLock)
            throw InsertionError.insertionRejected
        }
        try revalidateDynamicApplication(focusLock)
        return element
    }

    private func dynamicTextCapability(
        of element: AXUIElement,
        focusLock: InsertionFocusLock,
        noteTransient: ((DynamicCaptureReadinessStage) -> Void)? = nil
    ) throws {
        try revalidateDynamicApplication(focusLock)
        let supportsRange = environment.supportsSelectedTextRange(element)
        try revalidateDynamicApplication(focusLock)
        guard supportsRange == true else {
            noteTransient?(.textCapability)
            throw InsertionError.insertionRejected
        }
    }

    private func validateDynamicNonsecure(
        _ element: AXUIElement,
        focusLock: InsertionFocusLock,
        textCapabilityKnown: Bool,
        noteTransient: ((DynamicCaptureReadinessStage) -> Void)? = nil
    ) throws {
        try revalidateDynamicApplication(focusLock)
        let classification = environment.secureFieldClassification(
            element,
            textCapabilityKnown: textCapabilityKnown
        )
        // This check is intentionally after the final secure AX read. AX
        // cannot-complete and malformed values are `unknown`, never nonsecure.
        try revalidateDynamicApplication(focusLock)
        switch classification {
        case .secure:
            throw InsertionError.secureField
        case .nonsecure:
            return
        case .unknown:
            noteTransient?(.security)
            throw InsertionError.targetSecurityUnverifiable
        }
    }

    /// Password controls can have a different role from the captured composer,
    /// so detect an explicit secure subrole before applying the narrow editable
    /// leaf predicate. Unknown remains undecided until that stronger predicate
    /// succeeds and `validateDynamicNonsecure(..., true)` runs.
    private func rejectExplicitDynamicSecure(
        _ element: AXUIElement,
        focusLock: InsertionFocusLock
    ) throws {
        try revalidateDynamicApplication(focusLock)
        let classification = environment.secureFieldClassification(
            element,
            textCapabilityKnown: false
        )
        try revalidateDynamicApplication(focusLock)
        if classification == .secure {
            throw InsertionError.secureField
        }
    }

    private func validateMismatchedDynamicFocusIsNonsecure(
        _ element: AXUIElement,
        focusLock: InsertionFocusLock
    ) throws {
        try revalidateDynamicApplication(focusLock)
        let classification = environment.secureFieldClassification(
            element,
            textCapabilityKnown: false
        )
        try revalidateDynamicApplication(focusLock)
        switch classification {
        case .secure:
            throw InsertionError.secureField
        case .nonsecure:
            return
        case .unknown:
            do {
                try dynamicTextCapability(of: element, focusLock: focusLock)
                _ = try observedDynamicDescriptor(
                    of: element,
                    focusLock: focusLock
                )
                try validateDynamicNonsecure(
                    element,
                    focusLock: focusLock,
                    textCapabilityKnown: true
                )
            } catch let error as InsertionError
                where error == .insertionRejected
            {
                throw InsertionError.targetSecurityUnverifiable
            }
        }
    }

    private func observedDynamicDescriptor(
        of element: AXUIElement,
        focusLock: InsertionFocusLock,
        noteTransient: ((DynamicCaptureReadinessStage) -> Void)? = nil
    ) throws -> DynamicControlDescriptor {
        try revalidateDynamicApplication(focusLock)
        let descriptor = environment.dynamicControlDescriptor(of: element)
        try revalidateDynamicApplication(focusLock)
        guard let descriptor else {
            noteTransient?(.semanticDescriptor)
            throw InsertionError.insertionRejected
        }
        return descriptor
    }

    /// Observes the current app-focused text target without requiring a stable
    /// leaf proxy. Capability is read from one current proxy, then focus is
    /// reacquired and the newly current proxy is independently secure-checked
    /// and described. This is the logical pre-microphone contract.
    private func currentDynamicTextCapableSnapshot(
        for focusLock: InsertionFocusLock,
        matching identity: CapturedDynamicTargetIdentity? = nil,
        noteTransient: ((DynamicCaptureReadinessStage) -> Void)? = nil
    ) throws -> DynamicControlSnapshot {
        let capabilityElement = try currentDynamicFocusedElement(
            for: focusLock,
            noteTransient: noteTransient
        )
        try rejectExplicitDynamicSecure(
            capabilityElement,
            focusLock: focusLock
        )
        try dynamicTextCapability(
            of: capabilityElement,
            focusLock: focusLock,
            noteTransient: noteTransient
        )

        // Reacquire after capability enumeration. A same-app transition to a
        // distinct secure field must be classified on the current proxy, not
        // inferred from the old renderer proxy.
        let current = try currentDynamicFocusedElement(
            for: focusLock,
            noteTransient: noteTransient
        )
        try rejectExplicitDynamicSecure(current, focusLock: focusLock)
        try dynamicTextCapability(
            of: current,
            focusLock: focusLock,
            noteTransient: noteTransient
        )
        let descriptor = try observedDynamicDescriptor(
            of: current,
            focusLock: focusLock,
            noteTransient: noteTransient
        )
        // A missing subrole is explicit non-secure evidence only after the
        // descriptor has proved this is an allowed composer leaf, not one of
        // the many selected-range-capable ancestor groups/web areas.
        try validateDynamicNonsecure(
            current,
            focusLock: focusLock,
            textCapabilityKnown: true,
            noteTransient: noteTransient
        )
        if let identity, !dynamicDescriptor(descriptor, matches: identity) {
            noteTransient?(.stability)
            throw InsertionError.targetFieldChanged
        }
        let afterSecurity = try currentDynamicFocusedElement(
            for: focusLock,
            noteTransient: noteTransient
        )
        guard !CFEqual(afterSecurity, current) else {
            return DynamicControlSnapshot(
                element: current,
                descriptor: descriptor
            )
        }

        // Pre-microphone capture intentionally follows logical proxy churn.
        // If the renderer replaced the leaf during the final security read,
        // independently prove the newly current leaf instead of requiring
        // CFEqual stability. This also catches an old-nonsecure → new-secure
        // transition before capture can be accepted.
        try rejectExplicitDynamicSecure(afterSecurity, focusLock: focusLock)
        try dynamicTextCapability(
            of: afterSecurity,
            focusLock: focusLock,
            noteTransient: noteTransient
        )
        let latestDescriptor = try observedDynamicDescriptor(
            of: afterSecurity,
            focusLock: focusLock,
            noteTransient: noteTransient
        )
        try validateDynamicNonsecure(
            afterSecurity,
            focusLock: focusLock,
            textCapabilityKnown: true,
            noteTransient: noteTransient
        )
        if let identity,
            !dynamicDescriptor(latestDescriptor, matches: identity)
        {
            noteTransient?(.stability)
            throw InsertionError.targetFieldChanged
        }

        // The replacement checks above are separate blocking AX reads. Re-read
        // app focus once more after the last security classification so a
        // second transition cannot leave us returning a stale non-secure proxy
        // while a different, potentially secure, control is now focused.
        let finalCurrent = try currentDynamicFocusedElement(
            for: focusLock,
            noteTransient: noteTransient
        )
        guard CFEqual(finalCurrent, afterSecurity) else {
            try validateMismatchedDynamicFocusIsNonsecure(
                finalCurrent,
                focusLock: focusLock
            )
            noteTransient?(.stability)
            throw InsertionError.insertionRejected
        }
        return DynamicControlSnapshot(
            element: finalCurrent,
            descriptor: latestDescriptor
        )
    }

    @MainActor
    private func waitForDynamicTextCapableSnapshot(
        for focusLock: InsertionFocusLock,
        matching identity: CapturedDynamicTargetIdentity? = nil,
        shouldContinue: () -> Bool = { true }
    ) async throws -> DynamicControlSnapshot {
        var lastTransientError: InsertionError = .insertionRejected
        for attempt in 0..<Self.dynamicReadinessAttempts {
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            do {
                return try currentDynamicTextCapableSnapshot(
                    for: focusLock,
                    matching: identity
                )
            } catch let error as InsertionError {
                guard
                    error == .insertionRejected
                        || error == .targetSecurityUnverifiable
                else {
                    throw error
                }
                lastTransientError = error
            }
            guard attempt < Self.dynamicReadinessAttempts - 1 else { break }
            try await Task.sleep(
                nanoseconds: Self.dynamicReadinessDelayNanoseconds
            )
        }
        throw lastTransientError
    }

    /// Couples one selected-range observation to the still-current AX leaf.
    /// Leaf replacement is allowed between attempts, but never within the
    /// snapshot used as the Cmd+V baseline or receipt. A changed window or
    /// semantic field is terminal rather than renderer churn.
    private func currentDynamicPasteTargetEvidence(
        for focusLock: InsertionFocusLock,
        identity: CapturedDynamicTargetIdentity,
        requiresCollapsedRange: Bool
    ) throws -> DynamicPasteTargetEvidence {
        let snapshot = try currentDynamicTextCapableSnapshot(
            for: focusLock,
            matching: identity
        )
        try revalidateDynamicApplication(focusLock)
        let selectedRange = environment.selectedTextRange(of: snapshot.element)
        try revalidateDynamicApplication(focusLock)
        guard let selectedRange,
            selectedRange.location >= 0,
            selectedRange.length >= 0,
            !requiresCollapsedRange || selectedRange.length == 0
        else {
            throw InsertionError.insertionRejected
        }

        let current = try currentDynamicFocusedElement(for: focusLock)
        try rejectExplicitDynamicSecure(current, focusLock: focusLock)
        try dynamicTextCapability(of: current, focusLock: focusLock)
        let afterCapability = try currentDynamicFocusedElement(for: focusLock)
        try rejectExplicitDynamicSecure(
            afterCapability,
            focusLock: focusLock
        )
        let descriptor = try observedDynamicDescriptor(
            of: afterCapability,
            focusLock: focusLock
        )
        try validateDynamicNonsecure(
            afterCapability,
            focusLock: focusLock,
            textCapabilityKnown: true
        )
        guard dynamicDescriptor(descriptor, matches: identity) else {
            throw InsertionError.targetFieldChanged
        }
        guard CFEqual(current, snapshot.element),
            CFEqual(afterCapability, current)
        else {
            throw InsertionError.insertionRejected
        }
        let finalCurrent = try currentDynamicFocusedElement(for: focusLock)
        guard CFEqual(finalCurrent, afterCapability) else {
            try validateMismatchedDynamicFocusIsNonsecure(
                finalCurrent,
                focusLock: focusLock
            )
            throw InsertionError.insertionRejected
        }
        try rejectExplicitDynamicSecure(finalCurrent, focusLock: focusLock)
        try validateDynamicNonsecure(
            finalCurrent,
            focusLock: focusLock,
            textCapabilityKnown: true
        )
        let afterSecurity = try currentDynamicFocusedElement(for: focusLock)
        guard CFEqual(afterSecurity, finalCurrent) else {
            try validateMismatchedDynamicFocusIsNonsecure(
                afterSecurity,
                focusLock: focusLock
            )
            throw InsertionError.insertionRejected
        }
        return DynamicPasteTargetEvidence(
            element: afterSecurity,
            selectedTextRange: selectedRange
        )
    }

    @MainActor
    private func waitForDynamicPasteTargetEvidence(
        for focusLock: InsertionFocusLock,
        identity: CapturedDynamicTargetIdentity,
        requiresCollapsedRange: Bool
    ) async throws -> DynamicPasteTargetEvidence {
        var lastTransientError: InsertionError = .insertionRejected
        for attempt in 0..<Self.dynamicReadinessAttempts {
            try Task.checkCancellation()
            do {
                return try currentDynamicPasteTargetEvidence(
                    for: focusLock,
                    identity: identity,
                    requiresCollapsedRange: requiresCollapsedRange
                )
            } catch let error as InsertionError {
                guard
                    error == .insertionRejected
                        || error == .targetSecurityUnverifiable
                else {
                    throw error
                }
                lastTransientError = error
            }
            guard attempt < Self.dynamicReadinessAttempts - 1 else { break }
            try await Task.sleep(
                nanoseconds: Self.dynamicReadinessDelayNanoseconds
            )
        }
        throw lastTransientError
    }

    /// Compatibility APIs are synchronous, so they cannot suspend for
    /// renderer readiness. They may still consume a transient deterministic AX
    /// miss by repeating the observation immediately, but never sleep or block
    /// the main actor. Product ordinary dictation uses the async waiter above.
    private func retryDynamicPasteTargetEvidenceSynchronously(
        for focusLock: InsertionFocusLock,
        identity: CapturedDynamicTargetIdentity,
        requiresCollapsedRange: Bool
    ) throws -> DynamicPasteTargetEvidence {
        var lastTransientError: InsertionError = .insertionRejected
        for _ in 0..<Self.dynamicReadinessAttempts {
            do {
                return try currentDynamicPasteTargetEvidence(
                    for: focusLock,
                    identity: identity,
                    requiresCollapsedRange: requiresCollapsedRange
                )
            } catch let error as InsertionError {
                guard
                    error == .insertionRejected
                        || error == .targetSecurityUnverifiable
                else {
                    throw error
                }
                lastTransientError = error
            }
        }
        throw lastTransientError
    }

    /// Final synchronous event-boundary check for the exact leaf/range pair
    /// returned by the async resolver. The range is reread and must still equal
    /// the frozen evidence, then current focus/security are re-proved after that
    /// read before the single event is posted.
    private func validateDynamicEvidenceAtEvent(
        _ evidence: DynamicPasteTargetEvidence,
        focusLock: InsertionFocusLock,
        identity: CapturedDynamicTargetIdentity
    ) throws {
        let current = try currentDynamicFocusedElement(for: focusLock)
        try rejectExplicitDynamicSecure(current, focusLock: focusLock)
        try dynamicTextCapability(of: current, focusLock: focusLock)
        let afterCapability = try currentDynamicFocusedElement(for: focusLock)
        try rejectExplicitDynamicSecure(
            afterCapability,
            focusLock: focusLock
        )
        let descriptor = try observedDynamicDescriptor(
            of: afterCapability,
            focusLock: focusLock
        )
        try validateDynamicNonsecure(
            afterCapability,
            focusLock: focusLock,
            textCapabilityKnown: true
        )
        guard dynamicDescriptor(descriptor, matches: identity) else {
            throw InsertionError.targetFieldChanged
        }
        guard CFEqual(current, evidence.element),
            CFEqual(afterCapability, evidence.element)
        else {
            throw InsertionError.insertionRejected
        }
        let finalCurrent = try currentDynamicFocusedElement(for: focusLock)
        guard CFEqual(finalCurrent, evidence.element) else {
            try validateMismatchedDynamicFocusIsNonsecure(
                finalCurrent,
                focusLock: focusLock
            )
            throw InsertionError.insertionRejected
        }
        try revalidateDynamicApplication(focusLock)
        let finalRange = environment.selectedTextRange(of: finalCurrent)
        try revalidateDynamicApplication(focusLock)
        guard let finalRange,
            finalRange.location == evidence.selectedTextRange.location,
            finalRange.length == evidence.selectedTextRange.length
        else {
            throw InsertionError.insertionRejected
        }
        let afterRange = try currentDynamicFocusedElement(for: focusLock)
        guard CFEqual(afterRange, evidence.element) else {
            try validateMismatchedDynamicFocusIsNonsecure(
                afterRange,
                focusLock: focusLock
            )
            throw InsertionError.insertionRejected
        }
        try rejectExplicitDynamicSecure(afterRange, focusLock: focusLock)
        try validateDynamicNonsecure(
            afterRange,
            focusLock: focusLock,
            textCapabilityKnown: true
        )
        // Security classification is itself an AX read and may race a focus
        // transition. Reacquire once more so the event is posted only while
        // the proven non-secure evidence leaf is still the actual target.
        let afterSecurity = try currentDynamicFocusedElement(for: focusLock)
        guard CFEqual(afterSecurity, evidence.element) else {
            try validateMismatchedDynamicFocusIsNonsecure(
                afterSecurity,
                focusLock: focusLock
            )
            throw InsertionError.insertionRejected
        }
        try revalidateDynamicApplication(focusLock)
    }

    private func safeFocusedElement(
        for pid: pid_t,
        bundleID: String? = nil
    ) throws -> AXUIElement {
        guard let element = environment.focusedElement(for: pid) else {
            FlowLog.info("ax focus unavailable; refusing target")
            throw InsertionError.insertionRejected
        }
        try validateExactNonsecureTextControl(element)
        return element
    }

    /// Exact and protected targets may accept an absent subrole only after the
    /// control independently proves selected-range text capability. Explicit
    /// secure subroles are terminal, while AX read failures and malformed
    /// values remain unknown and fail closed.
    private func validateExactNonsecureTextControl(
        _ element: AXUIElement
    ) throws {
        let initial = environment.secureFieldClassification(
            element,
            textCapabilityKnown: false
        )
        if initial == .secure {
            throw InsertionError.secureField
        }
        guard environment.supportsSelectedTextRange(element) == true else {
            throw initial == .unknown
                ? InsertionError.targetSecurityUnverifiable
                : InsertionError.insertionRejected
        }
        switch environment.secureFieldClassification(
            element,
            textCapabilityKnown: true
        ) {
        case .secure:
            throw InsertionError.secureField
        case .nonsecure:
            return
        case .unknown:
            throw InsertionError.targetSecurityUnverifiable
        }
    }

    private func verifyIdentity(of focusLock: InsertionFocusLock) throws {
        guard
            focusLock.matches(
                processIdentifier: focusLock.processIdentifier,
                bundleIdentifier: environment.bundleIdentifier(for: focusLock.processIdentifier),
                appName: environment.appName(for: focusLock.processIdentifier)
            )
        else {
            throw InsertionError.focusChanged
        }
    }
}
