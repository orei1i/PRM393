using System;

namespace DomainLayer.Interfaces
{
    // Interface for basic entity with Id
    public interface IEntity
    {
        string Id { get; set; }
    }
}
