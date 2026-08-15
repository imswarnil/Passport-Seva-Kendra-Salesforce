/**
 * Transaction-scoped kill switches for PSK trigger automation.
 *
 * The demo data generator sets {@code bypassTriggers = true} so that it can own
 * child-record creation deterministically instead of racing the
 * PassportApplicationTriggerHandler. Always restore the previous value in a
 * finally block -- statics survive for the whole transaction.
 */
public with sharing class PSK_AutomationControl {

    /** When true, every PSK trigger handler returns immediately. */
    public static Boolean bypassTriggers = false;

    /**
     * Set while PaymentTriggerHandler rolls totals up to the parent application,
     * so the application handler can skip work that would otherwise re-run.
     */
    public static Boolean inPaymentRollup = false;

    /** Applications whose downstream artefacts (passport / print / dispatch) were already created. */
    public static Set<Id> issuanceProcessed = new Set<Id>();

    public static Boolean isBypassed() {
        return bypassTriggers == true;
    }

    /** Convenience for tests and scripts. */
    public static void reset() {
        bypassTriggers = false;
        inPaymentRollup = false;
        issuanceProcessed = new Set<Id>();
    }
}
