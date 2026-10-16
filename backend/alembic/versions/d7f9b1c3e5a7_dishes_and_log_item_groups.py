"""dishes and log item groups

Revision ID: d7f9b1c3e5a7
Revises: c5e7a9b1d283
Create Date: 2026-10-16 08:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'd7f9b1c3e5a7'
down_revision: Union[str, Sequence[str], None] = 'c5e7a9b1d283'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'dishes',
        sa.Column('id', sa.Text(), nullable=False),
        sa.Column('name', sa.Text(), nullable=False),
        sa.Column('aliases', postgresql.ARRAY(sa.Text()), server_default=sa.text("'{}'"), nullable=False),
        sa.Column('serving_g', sa.Float(), nullable=False),
        sa.Column('meal_kinds', postgresql.ARRAY(sa.Text()), server_default=sa.text("'{}'"), nullable=False),
        sa.Column('components', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('source_note', sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    # Nama hidangan induk (mis. "Ayam geprek") untuk komponen yang berasal dari satu hidangan; null untuk makanan tunggal.
    op.add_column('log_items', sa.Column('group_name', sa.Text(), nullable=True))
    op.add_column('log_items', sa.Column('role', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('log_items', 'role')
    op.drop_column('log_items', 'group_name')
    op.drop_table('dishes')
