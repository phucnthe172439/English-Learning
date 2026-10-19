using Learning_EngLish.Data;
using Learning_EngLish.DTOs;
using Learning_EngLish.Repositories;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace Learning_EngLish.Controllers;

[ApiController]
[Route("api/[controller]")]
public class WordTypeController : ControllerBase
{
    private readonly WordTypeRepository _repository;

    public WordTypeController(WordTypeRepository repository)
    {
        _repository = repository;
    }

    // GET: api/WordType
    [HttpGet]
    public async Task<ActionResult<List<WordTypeResponse>>> GetAll()
    {
        return await _repository.GetAllAsync();
    }

    // GET: api/WordType/5
    [HttpGet("{id:int}")]
    public async Task<ActionResult<WordTypeResponse>> GetById(int id)
    {
        var wordType = await _repository.GetByIdAsync(id);
        return wordType == null ? NotFound() : wordType;
    }

    // POST: api/WordType
    [HttpPost]
    public async Task<ActionResult<WordTypeResponse>> Create(WordTypeRequest request)
    {
        try
        {
            var id = await _repository.CreateAsync(request);
            var created = await _repository.GetByIdAsync(id);
            return CreatedAtAction(nameof(GetById), new { id }, created);
        }
        catch (SqlException ex) when (SqlErrors.IsDuplicate(ex.Number))
        {
            return Conflict($"Word type '{request.Name}' already exists.");
        }
    }

    // PUT: api/WordType/5
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, WordTypeRequest request)
    {
        try
        {
            var updated = await _repository.UpdateAsync(id, request);
            return updated ? NoContent() : NotFound();
        }
        catch (SqlException ex) when (SqlErrors.IsDuplicate(ex.Number))
        {
            return Conflict($"Word type '{request.Name}' already exists.");
        }
    }

    // DELETE: api/WordType/5
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        try
        {
            var deleted = await _repository.DeleteAsync(id);
            return deleted ? NoContent() : NotFound();
        }
        catch (SqlException ex) when (ex.Number == SqlErrors.ForeignKeyViolation)
        {
            return Conflict("This word type is still used by some words. Change them first.");
        }
    }
}
