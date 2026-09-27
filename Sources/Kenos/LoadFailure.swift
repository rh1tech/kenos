import Foundation

/// Why a page never arrived. The address stays in the field; this is what
/// Kenos says about it.
struct LoadFailure: Equatable {
    var code: Int
    var url: URL?

    var title: String {
        switch code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return L10n.tr("error.not_found.title")
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return L10n.tr("error.offline.title")
        case NSURLErrorTimedOut:
            return L10n.tr("error.timeout.title")
        case NSURLErrorCannotConnectToHost:
            return L10n.tr("error.refused.title")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorClientCertificateRejected, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorServerCertificateHasUnknownRoot:
            return L10n.tr("error.secure.title")
        default:
            return L10n.tr("error.generic.title")
        }
    }

    var detail: String {
        switch code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return L10n.tr("error.not_found.detail")
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return L10n.tr("error.offline.detail")
        case NSURLErrorTimedOut:
            return L10n.tr("error.timeout.detail")
        case NSURLErrorCannotConnectToHost:
            return L10n.tr("error.refused.detail")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorClientCertificateRejected, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorServerCertificateHasUnknownRoot:
            return L10n.tr("error.secure.detail")
        default:
            return L10n.tr("error.generic.detail")
        }
    }

    var codeLabel: String { L10n.tr("error.code", code) }
}
