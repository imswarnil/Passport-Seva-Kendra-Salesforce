@IsTest
private class PSK_ConstantsTest {

    @IsTest
    static void testLifecycleShape() {
        System.assertEquals(10, PSK_Constants.LIFECYCLE.size(),
            'The happy path has ten stages, Draft through Delivered');
        System.assertEquals(12, PSK_Constants.ALL_STATUSES.size(),
            'Twelve statuses including Rejected and Cancelled');
        System.assertEquals(PSK_Constants.STATUS_DRAFT, PSK_Constants.LIFECYCLE[0]);
        System.assertEquals(PSK_Constants.STATUS_DELIVERED,
            PSK_Constants.LIFECYCLE[PSK_Constants.LIFECYCLE.size() - 1]);
    }

    @IsTest
    static void testLifecycleIndex() {
        System.assertEquals(0, PSK_Constants.lifecycleIndex(PSK_Constants.STATUS_DRAFT));
        System.assertEquals(6, PSK_Constants.lifecycleIndex(PSK_Constants.STATUS_GRANTING));
        System.assertEquals(-1, PSK_Constants.lifecycleIndex(PSK_Constants.STATUS_REJECTED),
            'Rejected is off the happy path');
        System.assertEquals(-1, PSK_Constants.lifecycleIndex('Nonsense'));
        System.assertEquals(-1, PSK_Constants.lifecycleIndex(null));
    }

    @IsTest
    static void testIsAtOrBeyond() {
        System.assertEquals(true, PSK_Constants.isAtOrBeyond(
            PSK_Constants.STATUS_PRINTING, PSK_Constants.STATUS_GRANTING));
        System.assertEquals(true, PSK_Constants.isAtOrBeyond(
            PSK_Constants.STATUS_GRANTING, PSK_Constants.STATUS_GRANTING),
            'At the milestone counts as at-or-beyond');
        System.assertEquals(false, PSK_Constants.isAtOrBeyond(
            PSK_Constants.STATUS_PAID, PSK_Constants.STATUS_GRANTING));
        System.assertEquals(false, PSK_Constants.isAtOrBeyond(
            PSK_Constants.STATUS_REJECTED, PSK_Constants.STATUS_GRANTING),
            'A status off the happy path is never at-or-beyond a milestone');
        System.assertEquals(false, PSK_Constants.isAtOrBeyond(null, PSK_Constants.STATUS_DRAFT));
    }

    @IsTest
    static void testTerminalAndPaidSets() {
        System.assertEquals(3, PSK_Constants.TERMINAL_STATUSES.size());
        System.assertEquals(true,
            PSK_Constants.TERMINAL_STATUSES.contains(PSK_Constants.STATUS_CANCELLED));
        System.assertEquals(4, PSK_Constants.REQUIRES_PAID.size(),
            'Granting, Printing, Dispatch and Delivered all require a paid fee');
        System.assertEquals(false,
            PSK_Constants.REQUIRES_PAID.contains(PSK_Constants.STATUS_PAID),
            'The "Paid" STATUS is the fee-collected stage, not a payment guarantee');
    }

    @IsTest
    static void testValueSetsMatchMetadata() {
        System.assertEquals(36, PSK_Constants.INDIAN_STATES.size(),
            'The Indian_States global value set holds 28 states plus 8 union territories');
        System.assertEquals(6, PSK_Constants.APPLICATION_RECORD_TYPES.size());
        System.assertEquals(5, PSK_Constants.PAYMENT_STATUSES.size());
        System.assertEquals(6, PSK_Constants.PASSPORT_STATUSES.size());
        System.assertEquals(5, PSK_Constants.PASSPORT_STATUSES_NON_ORDINARY.size(),
            'Diplomatic and Official passports do not expose the Lost status');
        System.assertEquals(7, PSK_Constants.DISPATCH_STATUSES.size());
        System.assertEquals(6, PSK_Constants.PRINT_STATUSES.size());
        System.assertEquals(2, PSK_Constants.CLEARANCE_BY_CATEGORY.size());
        System.assertEquals(3,
            PSK_Constants.CLEARANCE_BY_CATEGORY.get('Diplomatic').size());
        System.assertEquals(2,
            PSK_Constants.CLEARANCE_BY_CATEGORY.get('Official').size());
    }
}
