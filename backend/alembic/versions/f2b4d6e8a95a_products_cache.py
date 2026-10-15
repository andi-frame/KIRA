"""products cache for barcode lookups

Revision ID: f2b4d6e8a95a
Revises: e1a3c5d7f849
Create Date: 2026-10-15 20:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'f2b4d6e8a95a'
down_revision: Union[str, Sequence[str], None] = 'e1a3c5d7f849'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'products',
        sa.Column('barcode', sa.Text(), nullable=False),
        sa.Column('found', sa.Boolean(), nullable=False),
        sa.Column('name', sa.Text(), nullable=True),
        sa.Column('brand', sa.Text(), nullable=True),
        sa.Column('serving_g', sa.Numeric(), nullable=True),
        sa.Column('is_drink', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('per100g', postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb"), nullable=False),
        sa.Column('fetched_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('barcode'),
    )


def downgrade() -> None:
    op.drop_table('products')
