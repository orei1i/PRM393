namespace DomainLayer.Enums
{
    /// <summary>
    /// Tracks the pricing health of a product relative to its latest calculated cost.
    /// Updated automatically whenever BasePrice or ProductCost changes.
    /// Does NOT affect IsAvailable — pricing status and menu availability are independent concerns.
    /// </summary>
    public enum PriceStatus
    {
        /// <summary>
        /// BasePrice is set and margin ≥ 20%.
        /// Formula: (BasePrice - Cost) / BasePrice ≥ 0.20
        /// </summary>
        Normal = 0,

        /// <summary>
        /// Margin is positive but below the 20% threshold.
        /// Formula: 0 ≤ (BasePrice - Cost) / BasePrice &lt; 0.20
        /// </summary>
        LowMargin = 1,

        /// <summary>
        /// BasePrice is lower than the latest calculated Cost.
        /// The product is being sold at a loss.
        /// </summary>
        BelowCost = 2
    }
}
